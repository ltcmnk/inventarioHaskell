-- ============================================================
-- Sistema de Inventario em Haskell
-- Atividade Avaliativa - RA2
-- Disciplina: Programacao Funcional
-- Professor: Frank Coelho de Alcantara
-- ============================================================

module Main where

import qualified Data.Map.Strict as Map
import Data.Map.Strict (Map)
import Data.List (maximumBy)
import Data.Ord (comparing)
import Data.Time (UTCTime, getCurrentTime, formatTime, defaultTimeLocale)
import Control.Exception (catch, IOException)
import System.IO (hSetBuffering, stdout, BufferMode(..))
import Data.Maybe (mapMaybe)

-- ============================================================
-- SECAO 1: TIPOS DE DADOS
-- ============================================================
-- Todos os tipos derivam Show e Read para serializacao em disco.

-- Representa um item do inventario
data Item = Item
    { itemID    :: String
    , nome      :: String
    , quantidade :: Int
    , categoria :: String
    } deriving (Show, Read, Eq)

-- O inventario e um mapa de ID -> Item
type Inventario = Map String Item

-- Tipo algebrico para as acoes registradas no log
data AcaoLog
    = Add
    | Remove
    | Update
    | List
    | Report
    | QueryFail
    deriving (Show, Read, Eq)

-- Tipo algebrico para o resultado de cada operacao
data StatusLog
    = Sucesso
    | Falha String
    deriving (Show, Read, Eq)

-- Registro completo de uma entrada no log de auditoria
data LogEntry = LogEntry
    { timestamp :: UTCTime
    , acao      :: AcaoLog
    , detalhes  :: String
    , status    :: StatusLog
    } deriving (Show, Read)

-- Alias para o resultado de uma operacao bem-sucedida
type ResultadoOperacao = (Inventario, LogEntry)


-- ============================================================
-- SECAO 2: LOGICA PURA (SEM IO)
-- ============================================================
-- Nenhuma funcao desta secao realiza operacoes de IO.
-- Toda a logica de negocio esta aqui.

-- Adiciona um novo item ao inventario.
-- Falha se o ID ja existir.
addItem :: UTCTime -> Item -> Inventario -> Either String ResultadoOperacao
addItem ts item inv
    | quantidade item < 0 =
        Left "Erro: quantidade inicial nao pode ser negativa."
    | null (itemID item) =
        Left "Erro: ID do item nao pode ser vazio."
    | null (nome item) =
        Left "Erro: nome do item nao pode ser vazio."
    | null (categoria item) =
        Left "Erro: categoria do item nao pode ser vazia."
    | otherwise =
        case Map.lookup (itemID item) inv of
            Just _  ->
                Left $ "Erro: item com ID '" ++ itemID item ++ "' ja existe no inventario."
            Nothing ->
                let novoInv = Map.insert (itemID item) item inv
                    entry   = LogEntry ts Add
                        ("Adicionado: " ++ itemID item ++ " | " ++ nome item
                        ++ " | Qtd: " ++ show (quantidade item)
                        ++ " | Cat: " ++ categoria item)
                        Sucesso
                in Right (novoInv, entry)

-- Remove unidades de um item existente.
-- Falha se o item nao existir ou se a quantidade for insuficiente.
removeItem :: UTCTime -> String -> Int -> Inventario -> Either String ResultadoOperacao
removeItem ts iid qtd inv
    | qtd <= 0 =
        Left "Erro: quantidade para remocao deve ser maior que zero."
    | otherwise =
        case Map.lookup iid inv of
            Nothing ->
                Left $ "Erro: item com ID '" ++ iid ++ "' nao encontrado."
            Just item ->
                if quantidade item < qtd
                    then Left $ "Erro: estoque insuficiente para '" ++ iid ++ "'. "
                             ++ "Disponivel: " ++ show (quantidade item)
                             ++ ", solicitado: " ++ show qtd ++ "."
                    else let novaQtd = quantidade item - qtd
                             itemAtualizado = item { quantidade = novaQtd }
                             novoInv = if novaQtd == 0
                                         then Map.delete iid inv
                                         else Map.insert iid itemAtualizado inv
                             entry = LogEntry ts Remove
                                 ("Removido: " ++ iid ++ " | Qtd removida: "
                                 ++ show qtd ++ " | Restante: " ++ show novaQtd)
                                 Sucesso
                         in Right (novoInv, entry)

-- Atualiza a quantidade de um item existente para um novo valor absoluto.
-- Falha se o item nao existir ou se a nova quantidade for negativa.
updateQty :: UTCTime -> String -> Int -> Inventario -> Either String ResultadoOperacao
updateQty ts iid novaQtd inv =
    case Map.lookup iid inv of
        Nothing ->
            Left $ "Erro: item com ID '" ++ iid ++ "' nao encontrado."
        Just item ->
            if novaQtd < 0
                then Left "Erro: quantidade nao pode ser negativa."
                else let itemAtualizado = item { quantidade = novaQtd }
                         novoInv = Map.insert iid itemAtualizado inv
                         entry   = LogEntry
                             { timestamp = ts
                             , acao      = Update
                             , detalhes  = "Atualizado: " ++ iid ++ " | Qtd anterior: "
                                           ++ show (quantidade item)
                                           ++ " -> Nova qtd: " ++ show novaQtd
                             , status    = Sucesso
                             }
                     in Right (novoInv, entry)

-- Retorna uma lista formatada dos itens do inventario.
listItems :: Inventario -> [String]
listItems inv
    | Map.null inv = ["Inventario vazio."]
    | otherwise    =
        let header = "ID            | Nome                    | Qtd   | Categoria"
            sep    = replicate 70 '-'
            linhas = map formatItem (Map.elems inv)
        in [header, sep] ++ linhas ++ [sep, "Total: " ++ show (Map.size inv) ++ " item(ns)."]
  where
    formatItem it =
        padR 14 (itemID it) ++ "| "
        ++ padR 25 (nome it) ++ "| "
        ++ padR 6  (show (quantidade it)) ++ "| "
        ++ categoria it
    padR n s = take n (s ++ repeat ' ')

-- Parser seguro para inteiros
lerInteiro :: String -> Maybe Int
lerInteiro texto =
    case reads texto :: [(Int, String)] of
        [(n, "")] -> Just n
        _         -> Nothing

-- ============================================================
-- SECAO 3: FUNCOES DE ANALISE DE LOG (PURAS)
-- ============================================================

-- Retorna todas as entradas de log referentes a um ID especifico.
historicoPorItem :: String -> [LogEntry] -> [LogEntry]
historicoPorItem iid = filter (itemMencionado iid . detalhes)
  where
    itemMencionado i d = i `elem` words (map (\c -> if c == ':' || c == '|' then ' ' else c) d)

-- Retorna apenas as entradas de log que registraram falha.
logsDeErro :: [LogEntry] -> [LogEntry]
logsDeErro = filter isFalha
  where
    isFalha entry = case status entry of
        Falha _ -> True
        Sucesso -> False

-- Retorna o ID do item que apareceu mais vezes no log (operacoes de sucesso).
itemMaisMovimentado :: [LogEntry] -> Maybe String
itemMaisMovimentado [] = Nothing
itemMaisMovimentado logs =
    let sucessos = filter (\e -> status e == Sucesso) logs
        contagem = foldr contarItem Map.empty sucessos
    in if Map.null contagem
        then Nothing
        else Just . fst . maximumBy (comparing snd) . Map.toList $ contagem
  where
    -- Extrai o ID (primeira palavra apos "Adicionado:", "Removido:" ou "Atualizado:")
    contarItem entry acc =
        case extrairID (detalhes entry) of
            Just iid -> Map.insertWith (+) iid 1 acc
            Nothing  -> acc
    extrairID d =
        let ws = words d
        in case ws of
            (_:iid:_) -> Just iid
            _         -> Nothing

-- Formata uma entrada de log para exibicao no terminal.
formatarLogEntry :: LogEntry -> String
formatarLogEntry entry =
    let ts  = formatTime defaultTimeLocale "%Y-%m-%d %H:%M:%S" (timestamp entry)
        ac  = show (acao entry)
        st  = case status entry of
                  Sucesso  -> "[OK]  "
                  Falha m  -> "[FAIL] " ++ m
    in ts ++ " | " ++ padR 11 ac ++ " | " ++ st ++ "\n       " ++ detalhes entry
  where
    padR n s = take n (s ++ repeat ' ')


-- ============================================================
-- SECAO 4: PERSISTENCIA (IO)
-- ============================================================

arquivoInventario :: FilePath
arquivoInventario = "Inventario.dat"

arquivoAuditoria :: FilePath
arquivoAuditoria = "Auditoria.log"

-- Carrega o inventario do disco. Se o arquivo nao existir, retorna mapa vazio.
carregarInventario :: IO Inventario
carregarInventario =
    catch lerArquivo tratarErro
  where
    lerArquivo = do
        conteudo <- readFile arquivoInventario
        if null conteudo
            then return Map.empty
            else case reads conteudo of
                [(inv, "")] -> return inv
                _           -> do
                    putStrLn "Aviso: nao foi possivel interpretar Inventario.dat. Iniciando vazio."
                    return Map.empty

    tratarErro :: IOException -> IO Inventario
    tratarErro _ = return Map.empty


-- Carrega o log de auditoria do disco. Se o arquivo nao existir, retorna lista vazia.
carregarLog :: IO [LogEntry]
carregarLog =
    catch lerArquivo tratarErro
  where
    lerArquivo = do
        conteudo <- readFile arquivoAuditoria
        let linhas = filter (not . null) (lines conteudo)
        return (mapMaybe parseLinha linhas)

    parseLinha linha =
        case reads linha of
            [(entry, "")] -> Just entry
            _             -> Nothing

    tratarErro :: IOException -> IO [LogEntry]
    tratarErro _ = return []

-- Salva o inventario completo em disco (sobrescreve o arquivo).
salvarInventario :: Inventario -> IO ()
salvarInventario inv =
    writeFile arquivoInventario (show inv)

-- Acrescenta uma entrada ao log de auditoria (nunca sobrescreve).
registrarLog :: LogEntry -> IO ()
registrarLog entry =
    appendFile arquivoAuditoria (show entry ++ "\n")


-- ============================================================
-- SECAO 5: DADOS INICIAIS
-- ============================================================
-- 10 itens para popular o sistema na primeira execucao.

itensIniciais :: [Item]
itensIniciais =
    [ Item "001" "Teclado Mecanico"   10  "Perifericos"
    , Item "002" "Mouse Sem Fio"      15  "Perifericos"
    , Item "003" "Monitor 24pol"      5   "Monitores"
    , Item "004" "Cabo HDMI 2m"       30  "Cabos"
    , Item "005" "Webcam HD"          8   "Perifericos"
    , Item "006" "SSD 480GB"          12  "Armazenamento"
    , Item "007" "Memoria RAM 8GB"    20  "Componentes"
    , Item "008" "Fonte 500W"         7   "Componentes"
    , Item "009" "Hub USB 4 Portas"   25  "Cabos"
    , Item "010" "Headset Gamer"      6   "Perifericos"
    ]

-- Insere os itens iniciais se o inventario estiver vazio.
popularInventario :: Inventario -> UTCTime -> IO (Inventario, [LogEntry])
popularInventario inv ts
    | not (Map.null inv) = return (inv, [])
    | otherwise = do
        putStrLn "Inventario vazio detectado. Inserindo 10 itens iniciais..."
        let resultados = foldr (inserirItem ts) (Right (inv, [])) itensIniciais
        case resultados of
            Left err         -> do
                putStrLn $ "Aviso ao popular: " ++ err
                return (inv, [])
            Right (novoInv, entradas) -> return (novoInv, entradas)
  where
    inserirItem t item acc =
        case acc of
            Left err -> Left err
            Right (invAcum, logs) ->
                case addItem t item invAcum of
                    Left err -> Left err
                    Right (invNovo, entry) -> Right (invNovo, entry : logs)


-- ============================================================
-- SECAO 6: PARSER E LOOP PRINCIPAL (IO)
-- ============================================================

-- Exibe o menu de ajuda ao usuario.
exibirMenu :: IO ()
exibirMenu = putStrLn $ unlines
    [ ""
    , "========================================="
    , "   SISTEMA DE INVENTARIO - COMANDOS"
    , "========================================="
    , "  add    - Adicionar novo item"
    , "  remove - Remover unidades de um item"
    , "  update - Atualizar quantidade de um item"
    , "  list   - Listar todos os itens"
    , "  report - Gerar relatorio de auditoria"
    , "  help   - Exibir este menu"
    , "  exit   - Encerrar o programa"
    , "========================================="
    ]

-- Le uma linha do usuario com um prompt personalizado.
lerLinha :: String -> IO String
lerLinha prompt = do
    putStr prompt
    line <- getLine
    return (trimStr line)
  where
    trimStr = reverse . dropWhile (== ' ') . reverse . dropWhile (== ' ')

-- Fluxo interativo para adicionar um item.
cmdAdd :: Inventario -> [LogEntry] -> IO (Inventario, [LogEntry])
cmdAdd inv logs = do
    ts   <- getCurrentTime
    iid  <- lerLinha "  ID do item    : "
    nm   <- lerLinha "  Nome          : "
    qtdS <- lerLinha "  Quantidade    : "
    cat  <- lerLinha "  Categoria     : "
    case lerInteiro qtdS of
        Just qtd ->
            let item = Item { itemID = iid, nome = nm, quantidade = qtd, categoria = cat }
            in case addItem ts item inv of
                Left err -> do
                    -- Operacao falhou: registra no log e mantém inventario
                    let entry = LogEntry ts Add ("Tentativa add ID=" ++ iid) (Falha err)
                    registrarLog entry
                    putStrLn $ "\n[ERRO] " ++ err
                    return (inv, entry : logs)
                Right (novoInv, entry) -> do
                    salvarInventario novoInv
                    registrarLog entry
                    putStrLn $ "\n[OK] Item '" ++ nm ++ "' adicionado com sucesso."
                    return (novoInv, entry : logs)
        _ -> do
            ts2 <- getCurrentTime
            let entry = LogEntry ts2 Add ("Tentativa add ID=" ++ iid) (Falha "Quantidade invalida")
            registrarLog entry
            putStrLn "\n[ERRO] Quantidade invalida. Digite um numero inteiro."
            return (inv, entry : logs)

-- Fluxo interativo para remover unidades de um item.
cmdRemove :: Inventario -> [LogEntry] -> IO (Inventario, [LogEntry])
cmdRemove inv logs = do
    ts   <- getCurrentTime
    iid  <- lerLinha "  ID do item    : "
    qtdS <- lerLinha "  Quantidade    : "
    case lerInteiro qtdS of
        Just qtd ->
            case removeItem ts iid qtd inv of
                Left err -> do
                    let entry = LogEntry ts Remove ("Tentativa remove ID=" ++ iid) (Falha err)
                    registrarLog entry
                    putStrLn $ "\n[ERRO] " ++ err
                    return (inv, entry : logs)
                Right (novoInv, entry) -> do
                    salvarInventario novoInv
                    registrarLog entry
                    putStrLn $ "\n[OK] " ++ show qtd ++ " unidade(s) removida(s) do item '" ++ iid ++ "'."
                    return (novoInv, entry : logs)
        _ -> do
            let entry = LogEntry ts Remove ("Tentativa remove ID=" ++ iid) (Falha "Quantidade invalida")
            registrarLog entry
            putStrLn "\n[ERRO] Quantidade invalida."
            return (inv, entry : logs)

-- Fluxo interativo para atualizar a quantidade de um item.
cmdUpdate :: Inventario -> [LogEntry] -> IO (Inventario, [LogEntry])
cmdUpdate inv logs = do
    ts   <- getCurrentTime
    iid  <- lerLinha "  ID do item    : "
    qtdS <- lerLinha "  Nova quantidade: "
    case lerInteiro qtdS of
        Just qtd ->
            case updateQty ts iid qtd inv of
                Left err -> do
                    let entry = LogEntry ts Update ("Tentativa update ID=" ++ iid) (Falha err)
                    registrarLog entry
                    putStrLn $ "\n[ERRO] " ++ err
                    return (inv, entry : logs)
                Right (novoInv, entry) -> do
                    salvarInventario novoInv
                    registrarLog entry
                    putStrLn $ "\n[OK] Quantidade do item '" ++ iid ++ "' atualizada para " ++ show qtd ++ "."
                    return (novoInv, entry : logs)
        _ -> do
            let entry = LogEntry ts Update ("Tentativa update ID=" ++ iid) (Falha "Quantidade invalida")
            registrarLog entry
            putStrLn "\n[ERRO] Quantidade invalida."
            return (inv, entry : logs)

-- Exibe todos os itens do inventario.
cmdList :: Inventario -> [LogEntry] -> IO [LogEntry]
cmdList inv logs = do
    ts <- getCurrentTime
    let entry = LogEntry ts List "Listagem do inventario solicitada." Sucesso
    registrarLog entry
    putStrLn ""
    mapM_ putStrLn (listItems inv)
    return (entry : logs)

-- Gera e exibe o relatorio completo de auditoria.
cmdReport :: [LogEntry] -> IO [LogEntry]
cmdReport logs = do
    ts <- getCurrentTime
    let entry = LogEntry ts Report "Relatorio de auditoria solicitado." Sucesso
        logsAtualizados = entry : logs

    registrarLog entry

    putStrLn ""
    putStrLn "========================================="
    putStrLn "         RELATORIO DE AUDITORIA"
    putStrLn "========================================="
    putStrLn $ "Total de operacoes registradas : " ++ show (length logsAtualizados)

    let erros = logsDeErro logsAtualizados
    putStrLn $ "Total de falhas                : " ++ show (length erros)

    case itemMaisMovimentado logsAtualizados of
        Nothing  -> putStrLn "Item mais movimentado          : (nenhum)"
        Just iid -> putStrLn $ "Item mais movimentado          : " ++ iid

    putStrLn ""
    putStrLn "----- Ultimas 5 operacoes -----"
    let recentes = take 5 (reverse logsAtualizados)
    if null recentes
        then putStrLn "(nenhuma operacao registrada)"
        else mapM_ (putStrLn . formatarLogEntry) recentes

    putStrLn ""
    putStrLn "----- Falhas Registradas -----"
    if null erros
        then putStrLn "(nenhuma falha registrada)"
        else mapM_ (putStrLn . formatarLogEntry) erros

    putStrLn ""
    putStrLn "----- Historico por item -----"
    lerLinha "  Digite o ID para filtrar (ou ENTER para pular): " >>= \filtro ->
        if null filtro
            then putStrLn "(ignorado)"
            else do
                let hist = historicoPorItem filtro logsAtualizados
                if null hist
                    then putStrLn $ "Nenhuma entrada encontrada para '" ++ filtro ++ "'."
                    else mapM_ (putStrLn . formatarLogEntry) hist

    putStrLn "========================================="
    return logsAtualizados

-- Loop principal do programa.
-- Mantem o estado (Inventario, [LogEntry]) entre os comandos.
loop :: Inventario -> [LogEntry] -> IO ()
loop inv logs = do
    cmd <- lerLinha "\n> "
    case cmd of
        "add"    -> do
            (inv', logs') <- cmdAdd inv logs
            loop inv' logs'
        "remove" -> do
            (inv', logs') <- cmdRemove inv logs
            loop inv' logs'
        "update" -> do
            (inv', logs') <- cmdUpdate inv logs
            loop inv' logs'
        "list"   -> do
            logs' <- cmdList inv logs
            loop inv logs'
        "report" -> do
            logs' <- cmdReport logs
            loop inv logs'
        "help"   -> do
            exibirMenu
            loop inv logs
        "exit"   -> do
            putStrLn "\nEncerrando o sistema. Ate logo!"
        _ -> do
            ts <- getCurrentTime
            let entry = LogEntry ts QueryFail
                    ("Comando desconhecido: " ++ cmd)
                    (Falha "Comando invalido.")
            registrarLog entry
            putStrLn $ "\n[AVISO] Comando desconhecido: '" ++ cmd ++ "'. Digite 'help' para ver os comandos."
            loop inv (entry : logs)

-- Ponto de entrada principal.
main :: IO ()
main = do
    hSetBuffering stdout NoBuffering
    putStrLn "========================================="
    putStrLn "   SISTEMA DE INVENTARIO - Haskell"
    putStrLn "========================================="
    putStrLn "Carregando dados..."

    -- Carrega estado anterior do disco
    inv  <- carregarInventario
    logs <- carregarLog

    putStrLn $ "Inventario carregado: " ++ show (Map.size inv) ++ " item(ns)."
    putStrLn $ "Log carregado       : " ++ show (length logs) ++ " entrada(s)."

    -- Popula com itens iniciais se necessario
    ts                <- getCurrentTime
    (invFinal, novosLogs) <- popularInventario inv ts

    -- Salva e registra se houve insercao inicial
    if not (null novosLogs)
        then do
            salvarInventario invFinal
            mapM_ registrarLog novosLogs
            putStrLn $ "Inseridos " ++ show (length novosLogs) ++ " itens iniciais."
        else return ()

    let logsAtuais = logs ++ novosLogs

    exibirMenu
    loop invFinal logsAtuais
