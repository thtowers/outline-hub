# Análise de Estrutura do Projeto

## Visão geral
Este repositório é um aplicativo Flutter com foco em simular a interface de um editor de código, com suporte para múltiplas plataformas (Android, Linux e Windows), seguindo a estrutura padrão de projetos Flutter.

## Estrutura de pastas
- `lib/`: código principal da aplicação.
  - `main.dart`: ponto de entrada e bootstrap do app.
  - `theme/`: tema visual e estilos globais.
  - `screens/`: composição de telas principais.
  - `widgets/`: componentes reutilizáveis de interface.
- `test/`: testes de widget.
- `android/`, `linux/`, `windows/`: runners e configurações por plataforma.

## Organização em camadas (estado atual)
A organização atual está orientada por UI, com separação por:
- **Entrada e configuração** (`main.dart`)
- **Composição de tela** (`screens/main_window.dart`)
- **Componentes visuais reutilizáveis** (`widgets/*`)
- **Estilo global** (`theme/app_theme.dart`)

Não há, no estado atual, uma camada explícita de domínio (regras de negócio), serviços, repositórios ou gerenciamento de estado mais robusto (como Provider, Riverpod, Bloc).

## Fluxo principal da aplicação
1. `main.dart` inicializa `MaterialApp` com tema escuro global.
2. A `MainWindow` mantém o estado principal da UI:
   - abas abertas;
   - aba ativa;
   - painel lateral direito (search/terminal).
3. `MainWindow` delega a renderização para widgets especializados:
   - `HeaderBar` (ações de topo);
   - `SideBar` (árvore e seleção de arquivo);
   - `DocumentView` (abas, edição e conteúdo por arquivo).
4. A troca de estado ocorre via callbacks (prop drilling) entre pai e filhos.

## Pontos fortes
- **Separação visual clara** entre tela principal, widgets e tema.
- **Boa legibilidade** para um protótipo de UI.
- **Callbacks explícitos** facilitam entender o fluxo de eventos.
- **Baixa complexidade inicial**, útil para prototipação rápida.

## Limitações arquiteturais observadas
- **Estado concentrado na UI** (`MainWindow` e `DocumentView`), dificultando escala.
- **Dados de arquivos em memória local** (`Map<String, String>`), sem persistência real.
- **Acoplamento entre componentes** por strings de arquivo e contratos implícitos.
- **Ausência de tipagem de domínio** (ex.: entidade `EditorTab`, `ProjectFile`).
- **Ausência de testes estruturais** focados em regras de tabs/edição/reordenação.

## Recomendações de evolução
1. **Extrair modelo de domínio leve**
   - Criar classes como `EditorTab`, `EditorDocument` e `PanelState`.
2. **Introduzir gerenciamento de estado escalável**
   - Começar com `ChangeNotifier`/`ValueNotifier` ou adotar `Riverpod`.
3. **Separar lógica de edição da UI**
   - Mover regras de tabs/reordenação/sincronização para um controller/service.
4. **Preparar persistência**
   - Introduzir camada de repositório para carregar/salvar conteúdo.
5. **Ampliar testes**
   - Cobrir invariantes de tabs (abrir/fechar/reordenar/trocar ativa).

## Conclusão
A estrutura atual é adequada para **protótipo de interface** e demonstra uma boa base de componentização. Para crescimento do projeto, o próximo passo recomendado é separar estado e regras de negócio da camada de widget, reduzindo acoplamento e aumentando testabilidade.
