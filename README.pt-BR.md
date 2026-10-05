<div align="center">

# 3dSlicerRouter

### Cada `.3mf` abre no fatiador certo, sozinho.

Dê dois cliques num 3MF no Mac. O 3dSlicerRouter lê a impressora salva dentro do arquivo e abre o
**Bambu Studio**, o **Snapmaker Orca** ou o fatiador que você escolher.

[![CI](https://github.com/MoraesGil/3dSlicerRouter/actions/workflows/ci.yml/badge.svg)](https://github.com/MoraesGil/3dSlicerRouter/actions/workflows/ci.yml)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-native-F05138?logo=swift&logoColor=white)
![Dependências](https://img.shields.io/badge/depend%C3%AAncias-0-brightgreen)
[![Licença: MIT](https://img.shields.io/badge/licen%C3%A7a-MIT-blue)](LICENSE)

<img src="docs/images/routing.svg" width="100%" alt="Animação: um projeto Bambu Lab A1 abre no Bambu Studio e um projeto Snapmaker U1 abre no Snapmaker Orca, porque o router lê o printer_model de cada arquivo">

[Instalar](docs/INSTALL.pt-BR.md) · [Testar com os samples](samples/) · [Como decide](#como-decide) · [English](README.md)

</div>

## O problema

Bambu Studio, Snapmaker Orca, OrcaSlicer e PrusaSlicer salvam `.3mf`, e o Finder só aceita um app
padrão para essa extensão. Com impressoras de duas marcas, você acaba abrindo um projeto do U1 no
Bambu Studio (ou um da A1 no Orca) e ganha aviso de preset, filamento faltando ou tipo de mesa trocado
sem perceber.

O 3dSlicerRouter vira o app padrão de `.3mf` e sai do caminho. Ele não tem janela: lê o `printer_model`
do projeto e entrega o arquivo ao fatiador dessa impressora.

## Qualquer impressora, qualquer fatiador

| | Impressora no arquivo | Abre no |
|:-:|---|---|
| <img src="docs/images/app-bambu-studio.png" width="40" alt="Bambu Studio"> | `Bambu Lab A1`, `A1 mini`, `P1S`, `X1C`, `H2D`, … | **Bambu Studio** |
| <img src="docs/images/app-snapmaker-orca.png" width="40" alt="Snapmaker Orca"> | `Snapmaker U1`, `J1`, `Artisan`, … | **Snapmaker Orca** |
| | Qualquer outra (`Original Prusa MK4S`, `Elegoo Centauri Carbon`, …) | **Você escolhe**, uma vez, e fica lembrado |

Impressora nova pergunta uma vez: Bambu Studio, Snapmaker Orca ou **Outro app…**, um seletor nativo
onde vale qualquer fatiador em `/Applications` (OrcaSlicer, PrusaSlicer, Creality Print, Elegoo
Slicer, Cura). Marque *Usar sempre para esta impressora* e nunca mais será perguntado. Também dá
para mapear pelo terminal:

```sh
3dSlicerRouter --map "Original Prusa MK4S" /Applications/PrusaSlicer.app
3dSlicerRouter --mappings
```

Precisa do outro fatiador para um arquivo? **Segure ⌥ (Option) ao abrir** e escolha. O *Abrir com*
do Finder continua funcionando, e o próximo duplo clique lê o arquivo de novo.

## Já está aberto? Nada de segunda janela

O Bambu Studio e o Snapmaker Orca abrem **outra instância** quando você abre um projeto que já está
aberto, e você acaba editando o mesmo arquivo em duas janelas. O 3dSlicerRouter confere antes. Se o
arquivo é o projeto aberto de um fatiador em execução, ele avisa, diz se há alterações não salvas e
oferece:

- **Ir para o fatiador**: traz exatamente aquela janela para a frente.
- **Recarregar do disco**: fecha esse projeto do jeito normal (o fatiador pergunta antes de descartar
  alterações) e reabre o arquivo salvo.
- **Abrir outra cópia**: o comportamento antigo, se você quiser mesmo.

Ele lê as pastas de recuperação que os fatiadores mantêm em `$TMPDIR` enquanto o projeto está
aberto, então não precisa de permissão extra. `3dSlicerRouter --inspect arq.3mf` mostra o mesmo.

## Veja para onde o arquivo vai antes de abrir

O router também ensina o Finder a mostrar projetos 3MF:

- **Lista e ícones pequenos** mostram o ícone do fatiador em que o arquivo vai abrir.
- **Ícones maiores, Galeria e painel de preview** mostram a mesa: a imagem salva pelo fatiador ou,
  quando o arquivo não tem, uma vista isométrica renderizada da mesa da impressora declarada.
- **Quick Look (Espaço)** em projeto de uma mesa é um 3D para girar e dar zoom. Projetos com várias
  mesas mostram todas lado a lado.

<p align="center">
<img src="docs/images/preview-bambu-h2d-four-plates.png" width="49%" alt="Preview gerado de um projeto Bambu Lab H2D com quatro mesas">
<img src="docs/images/preview-snapmaker-u1-four-colors.png" width="49%" alt="Preview gerado de um projeto Snapmaker U1 com quatro cores">
</p>

## Como decide

| Situação | Resultado |
|---|---|
| Primeira abertura | Fatiador mapeado para a impressora do arquivo; impressora desconhecida pergunta uma vez |
| Mesmo arquivo, mesma impressora | Onde abriu da última vez, inclusive escolha manual |
| Impressora mudou dentro da marca (A1 → A1 mini) | Mesmo fatiador, sem perguntar |
| Impressora mudou para Bambu Lab (U1 → A1) | Bambu Studio, sem perguntar |
| Impressora mudou para outra marca (A1 → U1) | Pergunta, com o fatiador mapeado em primeiro |
| Arquivo sem impressora | Classificador local opcional; senão, pergunta |
| ⌥ segurado ao abrir | Sempre pergunta |
| Arquivo já aberto num fatiador | Ir para ele, recarregar do disco ou abrir outra cópia |

A decisão fica num índice SQLite local e no arquivo, como atributo estendido
(`com.moraesdev.slicer-router`). Os fatiadores substituem o arquivo ao salvar, o que apaga o atributo;
o router então acha a decisão pelo caminho e grava de novo. **O router nunca altera o conteúdo do
arquivo.**

> Por que não o campo `Application`? O Snapmaker Orca também grava `BambuStudio-…` nele. A impressora
> vem de `Metadata/project_settings.config` → `printer_model`.

## Instalar

Precisa de macOS 14 ou mais novo e de pelo menos um fatiador.

```sh
brew install xcodegen
git clone https://github.com/MoraesGil/3dSlicerRouter.git && cd 3dSlicerRouter
./scripts/build.sh --install
alias 3dSlicerRouter=/Applications/3dSlicerRouter.app/Contents/MacOS/3dSlicerRouter   # coloque no ~/.zshrc
3dSlicerRouter --set-default
```

Prefere baixar pronto? O zip está em [Releases](https://github.com/MoraesGil/3dSlicerRouter/releases).
Dependências, atualização e **desinstalação**: [docs/INSTALL.pt-BR.md](docs/INSTALL.pt-BR.md).

## Teste

Seis projetos sintéticos pequenos em [`samples/`](samples/) cobrem todos os caminhos:

```sh
open samples/bambu-a1-keychain-tray.3mf        # Bambu Studio
open samples/snapmaker-u1-four-colors.3mf      # Snapmaker Orca
open samples/unknown-printer-prusa-mk4s.3mf    # pergunta uma vez
3dSlicerRouter --inspect samples/*.3mf         # mostra cada decisão, sem abrir nada
```

## Linha de comando

`3dSlicerRouter` é o alias da [instalação](#instalar), apontando para
`/Applications/3dSlicerRouter.app/Contents/MacOS/3dSlicerRouter`.

| Comando | O que faz |
|---|---|
| `--inspect arq.3mf…` | Impressora, thumbnail, memória e decisão, sem abrir nem gravar nada |
| `--map "<impressora>" /Applications/App.app` | Manda essa impressora para qualquer fatiador |
| `--mappings` | Lista os padrões por marca e os seus mapeamentos |
| `--render arq.3mf out.png [px]` | Preview isométrico da mesa em PNG |
| `--forget arq.3mf…` | Apaga a memória do router nesses arquivos |
| `--set-default` | Torna o router o app padrão de `.3mf` |

## Arquivos sem impressora (opcional)

Alguns 3MF não trazem nenhum metadado de fatiador. Para eles, o router pode consultar um modelo de
decisão local (o LAYA, por exemplo) por qualquer servidor que fale a API de escolha tipada
`/v1/systemone` e devolva probabilidades. Só abre direto com 75 % de confiança ou mais; abaixo disso
pergunta, com o palpite em primeiro. Se nada responder em `http://127.0.0.1:8100/v1/systemone`, ele
simplesmente pergunta.

```sh
defaults write com.moraesdev.3dslicerrouter LayaEndpoint off    # ou outra URL
```

## Perguntas frequentes

**Ele mexe nos meus arquivos?** Só num atributo estendido com a decisão. O conteúdo do 3MF continua
idêntico, byte a byte.

**O preview atualiza depois que edito o projeto?** Sim. O Finder guarda as thumbnails pela data de
modificação, então o próximo salvamento no fatiador atualiza o preview. Fechar sem salvar não muda nada.

**Precisa de permissão especial?** Não. Nada de Acessibilidade, Gravação de Tela ou Acesso Total ao
Disco. O macOS entrega a ele só o arquivo que você abriu.

**Manda dados para algum lugar?** Não. A única chamada de rede é o classificador opcional em `localhost`.

## Roadmap

- [ ] Padrões prontos para OrcaSlicer, PrusaSlicer, Elegoo Slicer e Creality Print (hoje: *Outro app…* ou `--map`)
- [ ] Janela de configurações para os mapeamentos impressora → fatiador
- [ ] Faces pintadas (multimaterial) no preview
- [ ] Release notarizado

Ideias, impressoras que roteiam errado e PRs são bem-vindos: [CONTRIBUTING.md](CONTRIBUTING.md).

## Aviso

Sem afiliação, endosso ou patrocínio da Bambu Lab ou da Snapmaker. Bambu Studio, Snapmaker Orca e
seus ícones são marcas dos respectivos donos, mostrados só para descrever compatibilidade.

## Licença

[MIT](LICENSE) © Gilberto Moraes ([@MoraesGil](https://github.com/MoraesGil))
