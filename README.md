# Flutter Code Editor Prototype

Projeto de interface de usuário para um editor de código moderno cruzando plataformas (Desktop e Web), todo desenvolvido em Flutter. 

## Recursos e UX
- **Tema Escuro Moderno:** Esquema de cores customizável focado em ambientes Desktop.
- **Abas Funcionais:** Crie, interaja, feche e reposicione (arrastando) abas como em navegadores e IDEs tradicionais.
- **Sidbar Navegável:** Árvore de arquivos com diretórios retráteis ("lib", "src") e seleção lógica.
- **Persistência Temporária:** Ao alternar de abas e voltar, o estado contido em texto se mantém perfeitamente com imutabilidade.

## Módulo de Estilização (Markdown)
Este editor utiliza atalhos nativos do Markdown para gerenciar o estilo do texto, garantindo compatibilidade com ferramentas como Obsidian e Notion:

### 1. Tamanho do Texto (Headings)
Os botões de aumentar (`+`) e diminuir (`-`) na barra superior transformam a linha atual em títulos:
- **Tamanho 28+**: Título 1 (`#`) - O maior tamanho.
- **Tamanho 22+**: Título 2 (`##`) - Tamanho grande.
- **Tamanho 18+**: Título 3 (`###`) - Tamanho médio.
- **Tamanho 14-16**: Texto Normal (Parágrafo).

### 2. Estilo Inline (Seleção)
Ao selecionar um texto com o mouse, você pode aplicar:
- **Negrito**: Atalho nativo `**texto**`.
- **Itálico**: Atalho nativo `_texto_`.

---

## Como Executar no Linux/Windows (Desktop)
1. Certifique-se de que tem os pré-requisitos para Desktop (SDK Windows ou dependências Linux).
2. Execute o comando de compilação:
   ```bash
   flutter run -d linux # ou windows
   ```
3. Alternativamente utilize sua IDE favorita selecionando "Windows (Desktop)" como target.
