<div align="center">

# 3dSlicerRouter

**Dê dois cliques em qualquer `.3mf` no Mac e ele abre no fatiador certo: Bambu Studio para impressoras
Bambu Lab, Snapmaker Orca para Snapmaker.** Chega de aviso de "projeto feito para outra impressora".

[Instalar](docs/INSTALL.pt-BR.md) · [Samples](samples/) · [Como decide](#como-decide) · [English](README.md)

<img src="docs/images/preview-h2d-four-plates.png" width="440" alt="Preview isométrico de um projeto Bambu Lab H2D com quatro mesas"> <img src="docs/images/preview-snapmaker-u1-four-colors.png" width="440" alt="Preview isométrico de um projeto Snapmaker U1 com quatro cores">

</div>

---

## Por quê

Quem tem impressoras de mais de uma marca vê todo `.3mf` igual no Finder, mas só um fatiador entende
cada arquivo de verdade. Abrir um projeto do Snapmaker U1 no Bambu Studio (ou o contrário) gera aviso de
preset, filamento faltando ou tipo de mesa trocado sem você perceber.

O **3dSlicerRouter** vira o app padrão de `.3mf`. Ele não abre o arquivo: lê para qual impressora o
projeto foi feito e entrega ao fatiador dessa impressora, em uma fração de segundo e sem janela própria.

## Recursos

- **Roteia pela impressora, não pelo nome do arquivo.** Lê o `printer_model` do projeto
  (`Bambu Lab A1`, `Bambu Lab H2D`, `Snapmaker U1`, …), então vale para qualquer modelo das duas marcas.
- **Lembra por arquivo.** A decisão fica num atributo estendido do próprio arquivo
  (`com.moraesdev.slicer-router`: UUID + decisão) e num índice SQLite local. Copiou o arquivo no APFS?
  A memória vai junto.
- **Percebe quando você muda a impressora do projeto.** A próxima abertura segue a nova impressora
  (veja as [regras](#como-decide)).
- **Qualquer impressora, qualquer fatiador.** Impressora nova pergunta uma vez: Bambu Studio, Snapmaker
  Orca ou *Outro app…* (seletor nativo em `/Applications`), com *Usar sempre para esta impressora*.
- **Segure ⌥ (Option) ao abrir** para escolher o fatiador daquele arquivo, por exemplo abrir um projeto
  do U1 no Bambu Studio e trocar para a A1. O *Abrir com* do Finder continua funcionando.
- **O Finder mostra para onde cada arquivo vai:**
  - **Lista e ícones pequenos** mostram o ícone do fatiador em que o arquivo vai abrir.
  - **Ícones médios/grandes, Galeria e painel de preview** mostram a mesa: a imagem salva pelo fatiador
    ou, sem ela, uma vista isométrica renderizada da mesa da impressora declarada com todas as mesas.
  - **Quick Look (Espaço)** em projeto de uma mesa é um 3D ao vivo para girar e dar zoom. Projetos com
    várias mesas mostram o render panorâmico.
- **Classificador opcional.** Arquivo sem impressora pode ser classificado por um serviço local de
  julgamento tipado ([LAYA](#opcional-classificador-laya)). Só abre direto com ≥ 75 % de confiança;
  abaixo disso pergunta, com o palpite em primeiro.
- **Zero dependências, 100 % nativo.** Zip, SQLite, SceneKit, Quick Look e LaunchServices são do macOS.
  A única chamada de rede é o classificador opcional em `localhost`.

## Como decide

| Situação | O que acontece |
|---|---|
| Primeira abertura, impressora `Bambu Lab …` | Abre no **Bambu Studio** |
| Primeira abertura, impressora `Snapmaker …` | Abre no **Snapmaker Orca** |
| Primeira abertura, impressora desconhecida (ex.: `Original Prusa MK4S`) | Pergunta uma vez; *Usar sempre* grava o mapeamento |
| Mesmo arquivo, mesma impressora | Abre onde abriu da última vez, inclusive escolha manual |
| Impressora mudou dentro da marca (A1 → A1 mini) | Mesmo fatiador, sem perguntar |
| Impressora mudou **para Bambu Lab** (ex.: U1 → A1) | Bambu Studio, sem perguntar |
| Impressora mudou para **outra marca** (ex.: A1 → U1) | Pergunta, com o fatiador mapeado sugerido |
| Sem impressora declarada | Classificador opcional; na dúvida, pergunta |
| Você segurou **⌥** ao abrir | Sempre pergunta |

> O metadado `Application` **não** é usado: o Snapmaker Orca também grava `BambuStudio-…` nele.
> A impressora vem de `Metadata/project_settings.config` → `printer_model`.

## Instalar

Requisitos: macOS 14 Sonoma ou mais novo, e Bambu Studio e/ou Snapmaker Orca.

```sh
brew install xcodegen                         # ferramenta de build (só para compilar)
git clone https://github.com/MoraesGil/3dSlicerRouter.git
cd 3dSlicerRouter
./scripts/build.sh --install                  # compila e copia para /Applications
/Applications/3dSlicerRouter.app/Contents/MacOS/3dSlicerRouter --set-default
```

Guia completo, download pronto, dependências e **desinstalação**: [docs/INSTALL.pt-BR.md](docs/INSTALL.pt-BR.md).

## Teste com os samples

A pasta [`samples/`](samples/) tem seis projetos sintéticos pequenos, um por caminho de decisão:

```sh
open samples/bambu-a1-keychain-tray.3mf          # → Bambu Studio
open samples/snapmaker-u1-four-colors.3mf        # → Snapmaker Orca
open samples/unknown-printer-prusa-mk4s.3mf      # → pergunta uma vez
```

Ou veja a decisão sem abrir nada:

```sh
/Applications/3dSlicerRouter.app/Contents/MacOS/3dSlicerRouter --inspect samples/*.3mf
```

## Linha de comando

```
3dSlicerRouter --inspect arq.3mf…            impressora, thumbnail, memória, decisão (não grava nada)
3dSlicerRouter --render arq.3mf out.png [px] preview isométrico da mesa em PNG
3dSlicerRouter --forget arq.3mf…             apaga a memória do router nesses arquivos
3dSlicerRouter --set-default                 torna o router o app padrão de .3mf
3dSlicerRouter --version
```

## Opcional: classificador LAYA

Só para arquivos **sem** impressora. O router envia uma pergunta `choice` com nome do arquivo, app de
origem, presets e nomes dos objetos para um endpoint local e espera:

```json
{ "answers": { "slicer": { "choice": "bambu_studio", "probabilities": { "bambu_studio": 0.91 } } } }
```

Endpoint padrão `http://127.0.0.1:8100/v1/systemone`. Se nada estiver ouvindo, o router pergunta na
hora, sem espera. Para trocar ou desligar:

```sh
defaults write com.moraesdev.3dslicerrouter LayaEndpoint http://127.0.0.1:9000/v1/systemone
defaults write com.moraesdev.3dslicerrouter LayaEndpoint off
```

## Aviso

Sem afiliação, endosso ou patrocínio da Bambu Lab ou da Snapmaker. Os nomes de produtos são marcas dos
respectivos donos e aparecem só para descrever compatibilidade.

## Licença

[MIT](LICENSE) © Gilberto Moraes ([@MoraesGil](https://github.com/MoraesGil))
