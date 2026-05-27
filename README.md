# Sistema de Inventário em Haskell

## Informações do Projeto

- **Instituição:** PUCPR
- **Disciplina:** Programação Funcional
- **Professor:** Frank Coelho de Alcantara
- **Atividade:** Avaliativa RA2

### Integrantes do Grupo (ordem alfabética)

| Nome | GitHub |
|------|--------|
| Letícia Miniuk Rosa Pereira | @ltcmnk |

---

## 🔗 Links

- **Repositório GitHub:** [https://github.com/ltcmnk/inventarioHaskell](https://github.com/ltcmnk/inventarioHaskell)
- **Ambiente Online (GBD):** [https://onlinegdb.com/Jp68oVRat](https://onlinegdb.com/Jp68oVRat)

---

## Descrição

Sistema de gerenciamento de inventário desenvolvido em Haskell, com foco em:

- **Programação funcional pura:** toda a lógica de negócio é implementada sem IO
- **Persistência em disco:** estado salvo em `Inventario.dat` e auditoria em `Auditoria.log`
- **Separação de responsabilidades:** tipos, lógica pura, persistência e IO claramente separados
- **Tratamento de erros:** uso de `Either` para falhas de lógica e `catch` para erros de IO

---

## Arquitetura

```
Main.hs
├── Seção 1 – Tipos de Dados
│   └── Item, Inventario, AcaoLog, StatusLog, LogEntry
├── Seção 2 – Lógica Pura (sem IO)
│   └── addItem, removeItem, updateQty, listItems
├── Seção 3 – Análise de Log (pura)
│   └── historicoPorItem, logsDeErro, itemMaisMovimentado
├── Seção 4 – Persistência (IO)
│   └── carregarInventario, carregarLog, salvarInventario, registrarLog
├── Seção 5 – Dados Iniciais
│   └── itensIniciais, popularInventario
└── Seção 6 – Loop Principal (IO)
    └── main, loop, cmdAdd, cmdRemove, cmdUpdate, cmdList, cmdReport
```

**Arquivos gerados em tempo de execução:**
- `Inventario.dat` — estado atual do inventário (sobrescrito a cada operação bem-sucedida)
- `Auditoria.log` — log append-only de todas as operações

---

## Como Executar

### No Online GDB

1. Acesse [https://www.onlinegdb.com/](https://www.onlinegdb.com/)
2. Selecione a linguagem **Haskell**
3. Apague o conteúdo padrão do editor
4. Cole o conteúdo completo de `Main.hs`
5. Clique em **Run**

### Compilação local (GHC)

```bash
ghc -o inventario Main.hs
./inventario
```

---

## Comandos Disponíveis

| Comando  | Descrição                                      |
|----------|------------------------------------------------|
| `add`    | Adicionar novo item ao inventário              |
| `remove` | Remover unidades de um item existente          |
| `update` | Atualizar a quantidade absoluta de um item     |
| `list`   | Listar todos os itens do inventário            |
| `report` | Exibir relatório de auditoria                  |
| `help`   | Exibir menu de ajuda                           |
| `exit`   | Encerrar o programa                            |

---

## Exemplo de Uso no Terminal

```
=========================================
   SISTEMA DE INVENTARIO - Haskell
=========================================
Carregando dados...
Inventario carregado: 0 item(ns).
Log carregado       : 0 entrada(s).
Inventario vazio detectado. Inserindo 10 itens iniciais...
Inseridos 10 itens iniciais.

=========================================
   SISTEMA DE INVENTARIO - COMANDOS
=========================================
  add    - Adicionar novo item
  remove - Remover unidades de um item
  update - Atualizar quantidade de um item
  list   - Listar todos os itens
  report - Gerar relatorio de auditoria
  help   - Exibir este menu
  exit   - Encerrar o programa
=========================================

> list

ID            | Nome                    | Qtd   | Categoria
----------------------------------------------------------------------
001           | Teclado Mecanico        | 10    | Perifericos
002           | Mouse Sem Fio           | 15    | Perifericos
...

> add
  ID do item    : 011
  Nome          : Impressora Laser
  Quantidade    : 4
  Categoria     : Impressoras

[OK] Item 'Impressora Laser' adicionado com sucesso.

> remove
  ID do item    : 001
  Quantidade    : 15

[ERRO] Erro: estoque insuficiente para '001'. Disponivel: 10, solicitado: 15.

> report
=========================================
         RELATORIO DE AUDITORIA
=========================================
Total de operacoes registradas : 12
Total de falhas                : 1
Item mais movimentado          : 001
...
```

---

## Cenários de Teste Manuais

### Cenário 1 — Persistência de Estado (Sucesso)

**Passos executados:**
1. Iniciado o programa sem arquivos `Inventario.dat` e `Auditoria.log` presentes
2. Executado `add` três vezes com os itens: "Teclado Sem Fio" (ID: 011), "Impressora Laser" (ID: 012), "Monitor Ultra HD" (ID: 013)
3. Executado `exit` para encerrar
4. Verificado que os arquivos `Inventario.dat` e `Auditoria.log` foram criados no diretório
5. Reiniciado o programa
6. Executado `list`

**Resultado esperado:** O inventário exibe os 3 itens inseridos na execução anterior.

**Resultado obtido:** ✅ Os 3 itens foram carregados corretamente do arquivo `Inventario.dat`.

---

### Cenário 2 — Erro de Lógica (Estoque Insuficiente)

**Passos executados:**
1. Executado `remove` com ID "001" e quantidade 15

**Resultado esperado:**
- Mensagem de erro clara no terminal
- `Inventario.dat` mantém 10 unidades
- `Auditoria.log` contém entrada com `Falha`

**Resultado obtido:** ✅
- Terminal exibiu: `[ERRO] Erro: estoque insuficiente para '001'. Disponivel: 10, solicitado: 15.`
- `Inventario.dat` permaneceu com 10 unidades
- `Auditoria.log` registrou `status = Falha "Erro: estoque insuficiente..."`

---

### Cenário 3 — Geração de Relatório de Erros

**Passos executados:**
1. Após o Cenário 2, executado `report`
2. Observada a seção "Falhas Registradas"

**Resultado esperado:** A função `logsDeErro` exibe a entrada referente à tentativa de remoção com estoque insuficiente.

**Resultado obtido:** ✅ O relatório exibiu corretamente a entrada de falha com timestamp, ação `Remove` e status `Falha "..."`.

---

## Critérios Atendidos

- [x] Tipos `Item`, `Inventario`, `AcaoLog`, `StatusLog`, `LogEntry` com `Show` e `Read`
- [x] `Data.Map` para `Inventario`
- [x] Funções puras `addItem`, `removeItem`, `updateQty` retornando `Either`
- [x] Funções de análise: `historicoPorItem`, `logsDeErro`, `itemMaisMovimentado`
- [x] `writeFile` para `Inventario.dat`, `appendFile` para `Auditoria.log`
- [x] `catch` para tratamento de ausência de arquivos na inicialização
- [x] 10 itens iniciais inseridos automaticamente
- [x] Loop interativo com comandos `add`, `remove`, `update`, `list`, `report`, `exit`
- [x] Separação rigorosa entre lógica pura e IO
- [x] Nomes de funções, tipos e arquivos conforme especificação
