# Instalar, atualizar e desinstalar

[English](INSTALL.md)

## Dependências

| | O quê | Para |
|---|---|---|
| **Para rodar** | macOS 14 Sonoma ou mais novo (Apple silicon ou Intel) | executar o app |
| | [Bambu Studio](https://bambulab.com/en/download/studio) e/ou [Snapmaker Orca](https://www.snapmaker.com/) em `/Applications` | os fatiadores de destino |
| | *(opcional)* um [classificador LAYA](../README.pt-BR.md#arquivos-sem-impressora-opcional) local | arquivos sem impressora declarada |
| **Para compilar** | Xcode 15 ou mais novo (só o Command Line Tools não basta) | compilar |
| | [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen` | gerar o projeto Xcode |
| *Opcional* | [duti](https://github.com/moretension/duti): `brew install duti` | trocar o app padrão pelo terminal |
| | Python 3 | só para regerar `samples/` |

**Nenhuma biblioteca de terceiros.** Leitura de zip, SQLite, render em SceneKit, Quick Look e
LaunchServices são todos do próprio macOS.

**Permissões:** nenhuma. O app não pede Acessibilidade, Gravação de Tela nem Acesso Total ao Disco.
O macOS entrega a ele só o arquivo em que você clicou. O preview da mesa é renderizado fora da tela e
não é screenshot de janela nenhuma.

## Opção A: compilar do código (recomendado)

```sh
brew install xcodegen
git clone https://github.com/MoraesGil/3dSlicerRouter.git
cd 3dSlicerRouter
./scripts/build.sh --install
/Applications/3dSlicerRouter.app/Contents/MacOS/3dSlicerRouter --set-default
```

O `build.sh --install`:

1. gera o `SlicerRouter.xcodeproj` e compila em Release com assinatura ad hoc;
2. copia o app para `/Applications/3dSlicerRouter.app` e registra no LaunchServices;
3. registra as duas extensões do Quick Look (thumbnail e preview);
4. abre o app uma vez em background (`--version`), porque o macOS só ativa as extensões de um app
   assinado ad hoc depois da primeira execução.

O `--set-default` torna o router o app padrão de `.3mf`. Pelo Finder dá no mesmo: selecione um `.3mf`
→ **Obter Informações** → **Abrir com: 3dSlicerRouter** → **Alterar Tudo…**.

### Conferir

```sh
/Applications/3dSlicerRouter.app/Contents/MacOS/3dSlicerRouter --inspect samples/*.3mf
duti -x 3mf                     # deve mostrar 3dSlicerRouter
```

O Finder pode segurar thumbnails antigas no cache por um tempo. `qlmanage -r cache` e reabrir o Finder
(⌥ + clique direito no ícone do Finder no Dock → *Reabrir*) atualizam.

## Opção B: download pronto

1. Baixe `3dSlicerRouter.zip` em [Releases](https://github.com/MoraesGil/3dSlicerRouter/releases).
2. Descompacte e arraste **3dSlicerRouter.app** para **/Applications**.
3. O build é assinado ad hoc, sem notarização. Remova a quarentena do download uma vez:
   ```sh
   xattr -dr com.apple.quarantine /Applications/3dSlicerRouter.app
   ```
4. Abra o app uma vez pelo `/Applications`. Uma janelinha explica o que ele faz; clique em
   **Tornar padrão para .3mf**.

## Atualizar

```sh
cd 3dSlicerRouter && git pull && ./scripts/build.sh --install
```

Os mapeamentos e a memória dos arquivos são mantidos.

## Desinstalar

```sh
./scripts/uninstall.sh                                # remove app + dados e devolve o .3mf ao Bambu Studio
./scripts/uninstall.sh com.snapmaker.snapmaker-orca   # …ou devolve para outro app
./scripts/uninstall.sh --purge-xattrs ~/Downloads     # e também limpa a memória dos arquivos dessa pasta
```

O que o script faz, se preferir fazer à mão:

1. **Remover o app e as extensões do Quick Look.**
   ```sh
   /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u /Applications/3dSlicerRouter.app
   rm -rf /Applications/3dSlicerRouter.app
   ```
2. **Devolver o `.3mf` a um fatiador, depois de remover o app** (é o app que declara o tipo `org.3mf.3mf`):
   `duti -s com.bambulab.bambu-studio .3mf all`, ou no Finder: **Obter Informações** → **Abrir com**
   → escolha o fatiador → **Alterar Tudo…**.
3. **Apagar os dados.**
   ```sh
   rm -rf ~/Library/Application\ Support/3dSlicerRouter      # índice SQLite (router.sqlite)
   defaults delete com.moraesdev.3dslicerrouter 2>/dev/null # configurações (endpoint LAYA)
   qlmanage -r cache                                        # limpa thumbnails em cache
   ```
4. *(Opcional)* **Remover a memória dos arquivos.** Cada arquivo roteado leva o atributo estendido
   `com.moraesdev.slicer-router`. É metadado inofensivo, mas dá para limpar:
   ```sh
   find ~/Downloads -name '*.3mf' -exec xattr -d com.moraesdev.slicer-router {} \; 2>/dev/null
   ```

Nada mais é instalado: sem launch agents, itens de login, extensões de kernel ou de sistema.

## Problemas comuns

| Sintoma | Solução |
|---|---|
| Dois cliques ainda abrem um fatiador direto | O arquivo tem *Sempre abrir com* do Finder: `xattr -d com.apple.LaunchServices.OpenWith arq.3mf` |
| Sem thumbnails ou previews | Abra o app uma vez (`open -a 3dSlicerRouter --args --version`) e rode `qlmanage -r cache` |
| `--set-default` aponta para uma pasta de build | As cópias de build têm o mesmo bundle id. Rode `./scripts/build.sh --install` de novo; ele as desregistra |
| "App danificado" / não abre (download) | `xattr -dr com.apple.quarantine /Applications/3dSlicerRouter.app` |
| Um arquivo continua indo para o fatiador errado | `3dSlicerRouter --forget arq.3mf`, ou segure ⌥ ao abrir para escolher de novo |
| Testar thumbnail pelo terminal trava | O `qlmanage -t` não é confiável com extensões modernas. Veja no Finder ou use `QLThumbnailGenerator` |
