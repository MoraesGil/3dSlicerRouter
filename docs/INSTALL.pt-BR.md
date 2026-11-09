# Instalar, atualizar e desinstalar

[English](INSTALL.md)

## Requisitos

- macOS 14 ou mais novo, em Apple silicon ou Intel.
- Pelo menos um fatiador instalado que abra arquivos 3MF, como OrcaSlicer, Bambu Studio ou Snapmaker Orca.
- Para compilar: Xcode 15 ou mais novo, suas ferramentas de linha de comando e [XcodeGen](https://github.com/yonaskolb/XcodeGen).

O app usa frameworks nativos do macOS. Não exige dependência de package manager em execução, serviço de rede, modelo de IA, conta nem API key.

## Compilar a partir do código

```sh
brew install xcodegen
git clone https://github.com/MoraesGil/3dSlicerRouter.git
cd 3dSlicerRouter
./scripts/build.sh --test --install
```

O script gera um app universal em Release. Ele assina o helper e as extensões antes do app principal, verifica as assinaturas e os entitlements das extensões e instala em `/Applications/3dSlicerRouter.app`.

Se o serviço de build do Xcode estiver indisponível, use as mesmas fontes e o mesmo SDK pelo backend CLI nativo:

```sh
./scripts/build.sh --native --test --install
```

Os dois backends exigem Xcode. O backend nativo usa `swiftc`, `lipo` e `xctest`; não instala outra toolchain.

Para usar o terminal, adicione este alias à configuração do shell:

```sh
alias 3dSlicerRouter=/Applications/3dSlicerRouter.app/Contents/MacOS/3dSlicerRouter
```

## Primeira execução e autorizações

1. Abra **3dSlicerRouter** em Aplicativos. Escolha **Tornar padrão para .3mf**. O Router permanece como padrão; cada arquivo pode abrir em um fatiador diferente.
2. As thumbnails e o Quick Look usam as duas extensões do app. Se o macOS as desativou, confira **Ajustes do Sistema → Geral → Itens de Início de Sessão e Extensões → Quick Look**. Os nomes podem variar entre versões do macOS.
3. A preparação de previews em background é opcional. Ative-a com `3dSlicerRouter --background on`. Se houver aprovação pendente, o app abre o painel nativo de Itens de Início para você autorizar.

Abrir um arquivo selecionado e renderizar seu preview não exige Acessibilidade nem Gravação de Tela. O indexador opcional pode provocar pedidos do macOS para pastas protegidas ou volumes removíveis. Registro autorizado e execução correta do worker são estados diferentes. Use `--index-status` e o log local para investigar falhas.

## Assinatura e downloads

O build padrão usa **assinatura ad-hoc**. Ele não tem assinatura Developer ID nem notarização. Uma assinatura local válida não comprova que o Gatekeeper aceitará um arquivo baixado em outro Mac.

Pacotes prontos, quando disponíveis, ficam em [Releases](https://github.com/MoraesGil/3dSlicerRouter/releases). Confira a versão e a origem antes de executar. Compilar localmente é o caminho suportado enquanto a distribuição notarizada permanece no roadmap. Não desative o Gatekeeper nem a segurança do sistema para instalar este app.

## Conferir a instalação

```sh
3dSlicerRouter --version
3dSlicerRouter --list-slicers
3dSlicerRouter --inspect samples/*.3mf
codesign --verify --deep --strict /Applications/3dSlicerRouter.app
```

A lista usa instalações válidas. Apps removidos, links quebrados e registros antigos do LaunchServices não viram botões do seletor. O sample sem impressora pergunta qual fatiador instalado deve ser usado.

Confira a associação no Finder: selecione um `.3mf` → **Obter Informações** → **Abrir com**. O app deve ser **3dSlicerRouter**. Também é possível configurar pelo CLI com `3dSlicerRouter --set-default`.

## Atualizar

```sh
git pull --ff-only
./scripts/build.sh --test --install
```

O instalador preserva o estado habilitado do indexador opcional e registra as extensões atualizadas. Os mapeamentos e as escolhas por arquivo permanecem nos dados do usuário. Confira qualquer autorização que o macOS pedir após a atualização.

## Desinstalar

```sh
./scripts/uninstall.sh
```

O script remove o app, encerra seu agente opcional, apaga catálogo, cache e logs locais e associa `.3mf` ao Bambu Studio quando `duti` estiver disponível. Para escolher outro substituto instalado:

```sh
./scripts/uninstall.sh com.orcaslicer.OrcaSlicer
```

Sem `duti`, escolha o substituto no Finder em **Obter Informações → Abrir com → Alterar Tudo…**. Nenhuma configuração de impressora ou fatiador é apagada.

Os atributos de roteamento dos arquivos são metadados e permanecem por padrão. Para removê-los explicitamente de uma pasta:

```sh
./scripts/uninstall.sh --purge-xattrs /caminho/da/pasta-de-3mf
```

## Solução de problemas

| Sintoma | Conferência |
|---|---|
| Dois cliques ignoram o Router | Pode haver uma escolha **Sempre abrir com** específica do arquivo no Finder. Confira em Obter Informações. |
| Thumbnail antiga | Salve o projeto, confira as extensões Quick Look e solicite o preview novamente. A imagem embutida de fallback pode estar antiga. |
| Abre no fatiador errado | Segure Option ao abrir e escolha novamente, ou use `--forget arq.3mf`. |
| Background habilitado, mas sem renders | Confira ociosidade, energia, execução do job e `~/Library/Logs/3dSlicerRouter/indexer.log`. Registro habilitado não comprova uma execução concluída. |
| Projeto grande mostra somente o preview salvo | Projetos comprimidos acima de 250 MB usam o fallback da primeira chapa embutida. |

Ao abrir uma issue, informe versão do macOS, versão do app e a saída sanitizada de `--inspect`. Não anexe credenciais, modelos de clientes nem caminhos privados.
