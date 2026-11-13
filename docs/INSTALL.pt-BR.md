# Instalar, atualizar e desinstalar

[English](INSTALL.md)

## Requisitos

- macOS 14 ou mais novo, em Apple silicon ou Intel.
- Pelo menos um fatiador instalado que abra arquivos 3MF, como OrcaSlicer, Bambu Studio ou Snapmaker Orca.
- Para compilar: Xcode 15 ou mais novo, suas ferramentas de linha de comando e [XcodeGen](https://github.com/yonaskolb/XcodeGen).

O app usa frameworks nativos do macOS. Não exige dependência de package manager em execução, serviço de rede, modelo de IA, conta nem API key.

## Baixar e instalar

1. **[Baixe 3dSlicerRouter.dmg](https://github.com/MoraesGil/3dSlicerRouter/releases/latest/download/3dSlicerRouter.dmg)** na [Release mais recente](https://github.com/MoraesGil/3dSlicerRouter/releases/latest). O mesmo app atende Apple silicon e Intel.
2. Abra o DMG. Arraste **3dSlicerRouter** para **Applications** nessa janela.
3. Ejete a imagem de disco. Abra **3dSlicerRouter** em **Aplicativos** e escolha **Usar para .3mf e .gcode**.

Você não precisa de Xcode, Homebrew, Git nem Terminal. Há também um ZIP: extraia-o e mova o app para Aplicativos. `SHA256SUMS` contém os hashes dos dois downloads.

Esta versão usa **assinatura ad-hoc**, sem Developer ID nem notarização. Se o macOS bloquear a primeira abertura e você confia no download, siga as [instruções da Apple para Abrir Mesmo Assim](https://support.apple.com/102445): tente abrir o app instalado, acesse **Ajustes do Sistema → Privacidade e Segurança → Abrir Mesmo Assim** e confirme. Macs gerenciados podem impedir essa autorização. Não desative o Gatekeeper nem remova a quarentena. Confira os limites desta distribuição em [Assinatura e downloads](#assinatura-e-downloads).

## Compilar a partir do código

Esta seção é para desenvolvedores. Ela não é necessária para instalar o download.

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

1. Abra **3dSlicerRouter** em Aplicativos. Escolha **Usar para .3mf e .gcode**. O Router permanece como padrão; cada arquivo pode abrir em um fatiador diferente.
2. As thumbnails e o Quick Look usam as duas extensões do app. Se o macOS as desativou, confira **Ajustes do Sistema → Geral → Itens de Início de Sessão e Extensões → Quick Look**. Os nomes podem variar entre versões do macOS.
3. A preparação de previews em background é opcional. Ative-a com `3dSlicerRouter --background on`. Se houver aprovação pendente, o app abre o painel nativo de Itens de Início para você autorizar.

Abrir um arquivo selecionado e renderizar seu preview não exige Acessibilidade nem Gravação de Tela. O indexador opcional pode provocar pedidos do macOS para pastas protegidas ou volumes removíveis. Registro autorizado e execução correta do worker são estados diferentes. Use `--index-status` e o log local para investigar falhas.

## Ícones dos arquivos no Finder

Os ícones pequenos mantêm a logo do Router. A cor da borda e o marcador indicam o slicer escolhido: Bambu Studio (B), OrcaSlicer (O), Snapmaker Orca (S), PrusaSlicer (P), Cura (C), Creality Print (CR) ou Elegoo (E). Slicers desconhecidos usam o Router neutro (R). As miniaturas grandes e o Quick Look continuam mostrando a peça ou o toolpath.

No G-code, a escolha manual salva tem prioridade. Depois vêm o mapeamento explícito da impressora e o gerador declarado. O padrão de uma marca não substitui um gerador reconhecido. Segure Option ao abrir para escolher novamente.

Os ícones são atualizados ao abrir ou indexar o arquivo, ou ao solicitar uma thumbnail pequena. Para atualizar arquivos existentes sem abrir um slicer, abra o Router, escolha **Atualizar ícones de arquivos…** e selecione os arquivos. Isso altera metadados de ícone do Finder, sem mudar o conteúdo do arquivo. Arquivos somente leitura ou em sistemas sem suporte a esses metadados podem manter um ícone de fallback.

## Assinatura e downloads

O build padrão usa **assinatura ad-hoc**. Ele não tem assinatura Developer ID nem notarização. Uma assinatura local válida não comprova que o Gatekeeper aceitará um arquivo baixado em outro Mac.

Os downloads de DMG e ZIP ficam em [Releases](https://github.com/MoraesGil/3dSlicerRouter/releases). Confira a versão e a origem antes de executar. O DMG facilita a cópia do app; ele não fornece notarização. A autorização do build baixado e a ativação das extensões Quick Look em um Mac sem instalação anterior ainda exigem validação própria. Não desative o Gatekeeper nem a segurança do sistema para instalar este app.

## Conferir a instalação

```sh
3dSlicerRouter --version
3dSlicerRouter --list-slicers
3dSlicerRouter --inspect samples/*.3mf
codesign --verify --deep --strict /Applications/3dSlicerRouter.app
```

A lista usa instalações válidas. Apps removidos, links quebrados e registros antigos do LaunchServices não viram botões do seletor. O sample sem impressora pergunta qual fatiador instalado deve ser usado.

Confira a associação no Finder: selecione um `.3mf` → **Obter Informações** → **Abrir com**. O app deve ser **3dSlicerRouter**. Também é possível configurar pelo CLI com `3dSlicerRouter --set-default`.


### Limitação do helper ad-hoc

A execução automática do indexador ainda é experimental em builds ad-hoc. O macOS pode rejeitar o
lançamento com `EX_CONFIG` (78) ou `Launch Constraint Violation` mesmo quando o registro aparece
habilitado. A validação local observou esse caso; não há correção baseada em desativar a segurança.
Os previews sob demanda continuam disponíveis. Use `--render` ou `--index` em foreground se necessário.

## Atualizar

1. Baixe o DMG mais recente em [Releases](https://github.com/MoraesGil/3dSlicerRouter/releases/latest).
2. Feche o 3dSlicerRouter. Se você ativou o item opcional em background, desligue-o em **Ajustes do Sistema → Geral → Itens de Início de Sessão** antes de substituir o app.
3. Arraste o app novo para **Aplicativos** e escolha **Substituir**. Ejete a imagem e abra o app instalado. Confira novas autorizações do macOS e reative o item em background, se necessário.

Os mapeamentos e as escolhas por arquivo permanecem nos dados do usuário. Não há atualizador automático.

Para uma instalação a partir do código:

```sh
git pull --ff-only
./scripts/build.sh --test --install
```

O script de build preserva o estado habilitado do indexador opcional e registra as extensões atualizadas. Confira qualquer autorização que o macOS pedir após a atualização.

## Desinstalar

Desative o item opcional em background nos Ajustes do Sistema, se estiver ativo. Mova **3dSlicerRouter** de **Aplicativos** para a Lixeira. No Finder, use **Obter Informações → Abrir com → Alterar Tudo…** para associar `.3mf` e `.gcode` a outro fatiador instalado. Isso mantém catálogo, cache, logs e escolhas de roteamento nos dados do usuário.

Para uma instalação a partir do código, este script também remove catálogo, cache de previews e logs do app:

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
