<div align="center">

# 3dSlicerRouter

### Cada `.3mf` abre no fatiador certo, sozinho.

Dê dois cliques num 3MF no Mac. O 3dSlicerRouter lê a impressora salva dentro do arquivo e abre o
**Bambu Studio**, o **OrcaSlicer**, o **Snapmaker Orca** ou o fatiador que você escolher.

[![CI](https://github.com/MoraesGil/3dSlicerRouter/actions/workflows/ci.yml/badge.svg)](https://github.com/MoraesGil/3dSlicerRouter/actions/workflows/ci.yml)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-native-F05138?logo=swift&logoColor=white)
![Dependências](https://img.shields.io/badge/depend%C3%AAncias-0-brightgreen)
[![Licença: MIT](https://img.shields.io/badge/licen%C3%A7a-MIT-blue)](LICENSE)

<img src="docs/images/routing.svg" width="100%" alt="Animação: um projeto Bambu Lab A1 abre no Bambu Studio e um projeto Snapmaker U1 abre no OrcaSlicer, porque o router lê o printer_model de cada arquivo">

[Instalar](docs/INSTALL.pt-BR.md) · [Testar com os samples](samples/) · [Como decide](#como-decide) · [English](README.md)

</div>

## O problema

Bambu Studio, Snapmaker Orca, OrcaSlicer e PrusaSlicer salvam `.3mf`, e o Finder só aceita um app
padrão para essa extensão. Com impressoras de duas marcas, você acaba abrindo um projeto do U1 no
Bambu Studio (ou um da A1 no Orca) e ganha aviso de preset, filamento faltando ou tipo de mesa trocado
sem perceber.

O 3dSlicerRouter vira o app padrão de `.3mf` e sai do caminho. Ele lê o `printer_model` do projeto e entrega o arquivo ao fatiador configurado.
Sem essa informação, pergunta qual fatiador instalado você quer usar.

## Qualquer impressora, qualquer fatiador

| | Impressora no arquivo | Abre no |
|:-:|---|---|
| <img src="docs/images/app-bambu-studio.png" width="40" alt="Bambu Studio"> | `Bambu Lab A1`, `A1 mini`, `P1S`, `X1C`, `H2D`, … | **Bambu Studio** |
| | `Snapmaker U1`, `J1`, `Artisan`, … | **OrcaSlicer oficial** |
| | `Prusa`, `Original Prusa`, … | **OrcaSlicer oficial** |
| | Qualquer outra (`Elegoo Centauri Carbon`, …) | **OrcaSlicer oficial** |
| | Sem impressora declarada | **Pergunta entre os fatiadores instalados** |

O OrcaSlicer oficial é o padrão para projetos novos de impressoras que não são Bambu. Segure Option
ao abrir para escolher entre os fatiadores instalados ou **Outro app…**, um seletor nativo
para os fatiadores em `/Applications`. Marque *Usar sempre para esta impressora* para definir
uma regra para aquele modelo. Também dá para mapear pelo terminal:

```sh
3dSlicerRouter --map "Original Prusa MK4S" /Applications/PrusaSlicer.app
3dSlicerRouter --mappings
```

Precisa do outro fatiador para um arquivo? **Segure ⌥ (Option) ao abrir** e escolha. O *Abrir com*
do Finder continua funcionando, e o próximo duplo clique lê o arquivo de novo.

## Já está aberto? Nada de segunda janela

O Bambu Studio, o OrcaSlicer e o Snapmaker Orca abrem **outra instância** quando você abre um projeto que já está
aberto, e você acaba editando o mesmo arquivo em duas janelas. O 3dSlicerRouter confere antes. Se o
arquivo é o projeto aberto de um fatiador em execução, ele avisa, diz se há alterações não salvas e
oferece:

- **Ir para o fatiador**: ativa a instância do fatiador em execução.
- **Reiniciar e recarregar**: fecha a instância do fatiador, que pode conter outras janelas. O fatiador
  pode perguntar sobre alterações não salvas antes de reabrir o arquivo do disco.
- **Abrir outra cópia**: o comportamento antigo, se você quiser mesmo.

Ele lê as pastas de recuperação que os fatiadores mantêm em `$TMPDIR` enquanto o projeto está
aberto, então não precisa de permissão extra. `3dSlicerRouter --inspect arq.3mf` mostra o mesmo.

## Thumbnails do Finder e previews 3D

O router também ensina o Finder a mostrar projetos 3MF:

- **Thumbnails do Finder em todos os tamanhos** mostram a primeira chapa. O render indexado da revisão
  atual tem prioridade; sem ele, a solicitação renderiza a geometria atual. A imagem salva pelo fatiador
  só é usada se o render falhar ou o projeto comprimido exceder 250 MB; esse fallback pode estar desatualizado.
- **Quick Look (Espaço)** em projeto de uma mesa é um 3D para girar e dar zoom. Projetos com várias
  mesas mostram todas lado a lado.
- **Cores pintadas exatas.** Faces pintadas com o pincel de cor do fatiador são decodificadas triângulo
  a triângulo (a mesma árvore de subdivisão que o Bambu Studio e o Orca salvam): modelo de quatro cores
  aparece com quatro cores.
- **G-code também.** Arquivos `.gcode` mostram a thumbnail embutida ou, sem ela, o caminho de extrusão
  desenhado na cor do filamento de cada ferramenta. O Espaço abre em 3D.

<p align="center">
<img src="docs/images/preview-bambu-h2d-four-plates.png" width="49%" alt="Preview gerado de um projeto Bambu Lab H2D com quatro mesas">
<img src="docs/images/preview-snapmaker-u1-painted-faces.png" width="49%" alt="Preview gerado de um cubo Snapmaker U1 com faces pintadas em quatro cores de filamento">
</p>

## Previews em background (opcional)

Projetos grandes levam segundos para renderizar. Ligue o indexador e eles ficam prontos antes de você
abrir o Finder:

```sh
3dSlicerRouter --background on
```

- Acha todos os `.3mf` e `.gcode` do Mac pelo Spotlight (sem varrer o disco) e mantém um catálogo.
- Acorda a cada 30 minutos com prioridade de background e **só trabalha na tomada, fora do modo de pouca
  energia, com o Mac frio e você ausente há 3 minutos**. Para assim que você volta.
- Os previews ficam em `~/Library/Application Support/3dSlicerRouter/previews`. Salvar invalida a imagem
  gerada, inclusive com o mesmo tamanho dentro do mesmo segundo. A próxima passada elegível renderiza a
  geometria atual da primeira chapa mesmo com imagem embutida antiga e avisa o Finder. Falhas e caches ausentes são repetidos.
- O macOS mostra *Item de segundo plano adicionado*. Dá para desligar em **Ajustes do Sistema › Geral ›
  Itens de Início** ou com `3dSlicerRouter --background off`. Na primeira vez que ele ler arquivos da
  Mesa, Documentos, Downloads ou de um disco externo, o macOS pode pedir sua autorização.

`3dSlicerRouter --index-status` mostra o que ele está fazendo; o log fica em `~/Library/Logs/3dSlicerRouter/indexer.log`.

## Como decide

| Situação | Resultado |
|---|---|
| Primeira abertura | Regra explícita da impressora; sem regra, Bambu Studio para Bambu Lab e OrcaSlicer oficial para as demais |
| Mesmo arquivo, mesma impressora | Onde abriu da última vez, inclusive escolha manual |
| Impressora mudou dentro da marca (A1 → A1 mini) | Mesmo fatiador, sem perguntar |
| Impressora mudou para Bambu Lab (U1 → A1) | Bambu Studio, sem perguntar |
| Impressora mudou para outra marca (A1 → U1) | Pergunta, com o fatiador mapeado em primeiro |
| Arquivo sem impressora | Escolha manual salva; sem escolha manual, pergunta entre os fatiadores instalados |
| Fatiador definido foi desinstalado | Pergunta entre os fatiadores ainda instalados |
| ⌥ segurado ao abrir | Sempre pergunta |
| Arquivo já aberto num fatiador | Ir para ele, reiniciar e recarregar ou abrir outra cópia |

A decisão fica num índice SQLite local e no arquivo, como atributo estendido
(`com.moraesdev.slicer-router`). Os fatiadores substituem o arquivo ao salvar, o que apaga o atributo;
o router então acha a decisão pelo caminho e grava de novo. **O router nunca altera o conteúdo do
arquivo.**

Cada escolha registra bundle ID, caminho e nome do aplicativo. O OrcaSlicer oficial
(`com.orcaslicer.OrcaSlicer`, `/Applications/OrcaSlicer.app`) e o Snapmaker Orca
(`com.snapmaker.snapmaker-orca`, `/Applications/Snapmaker Orca.app`) são escolhas separadas.
As escolhas salvas por arquivo e as regras explícitas por impressora têm prioridade sobre o novo padrão.
O caminho registrado tem prioridade enquanto o aplicativo nele tiver o bundle ID correspondente.
Abrir o arquivo diretamente em outro slicer não atualiza a escolha do router.

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

Pacotes prontos, quando disponíveis, ficam em [Releases](https://github.com/MoraesGil/3dSlicerRouter/releases).
O build local usa assinatura ad-hoc. O script não fornece assinatura Developer ID nem notarização.
Dependências, atualização e **desinstalação**: [docs/INSTALL.pt-BR.md](docs/INSTALL.pt-BR.md).

Se o serviço de build do Xcode travar, `./scripts/build.sh --native --test` gera o mesmo app universal e
roda a suíte completa com `swiftc` e `xctest`. O SDK e as ferramentas de linha de comando do Xcode continuam necessários.

## Teste

Sete projetos sintéticos pequenos em [`samples/`](samples/) cobrem todos os caminhos:

```sh
open samples/bambu-a1-keychain-tray.3mf        # Bambu Studio
open samples/snapmaker-u1-four-colors.3mf      # OrcaSlicer
open samples/no-printer-declared.3mf          # escolher um fatiador instalado
3dSlicerRouter --inspect samples/*.3mf         # mostra cada decisão, sem abrir nada
```

## Linha de comando

`3dSlicerRouter` é o alias da [instalação](#instalar), apontando para
`/Applications/3dSlicerRouter.app/Contents/MacOS/3dSlicerRouter`.

| Comando | O que faz |
|---|---|
| `--inspect arq.3mf…` | Impressora, thumbnail, escolha salva e decisão; não abre fatiador nem altera o 3MF |
| `--map "<impressora>" /Applications/App.app` | Manda essa impressora para qualquer fatiador |
| `--mappings` | Lista os padrões por marca e os seus mapeamentos |
| `--list-slicers` | Lista somente os fatiadores instalados e seus caminhos |
| `--render arq.3mf\|arq.gcode out.png [px]` | Preview isométrico em PNG |
| `--background on\|off\|status` | Indexador de previews em background |
| `--index [--limit N]` | Indexa e renderiza agora, ignorando a regra de ociosidade |
| `--index-status` | Estado do indexador, totais do catálogo e caminho do log |
| `--catalog [texto]` | Todos os 3MF e G-code achados, com impressora e estado do preview |
| `--forget arq.3mf…` | Apaga a memória do router nesses arquivos |
| `--set-default` | Torna o router o app padrão de `.3mf` |

## Arquivos sem impressora

Arquivos sem impressora declarada perguntam qual fatiador usar. O seletor verifica instalações
em `/Applications`, `~/Applications`, suas subpastas e os registros dos três fatiadores principais
no macOS. Só entram apps com executável presente, incluindo PrusaSlicer e outros fatiadores
reconhecidos quando instalados. Apps removidos e links quebrados ficam fora da lista.

Uma escolha manual salva continua válida para aquele arquivo. Decisões automáticas antigas
que usavam OrcaSlicer por falta de impressora voltam a perguntar. As regras são executadas localmente. O 3dSlicerRouter continua como app padrão da extensão `.3mf`.

<p align="center">
<img src="docs/images/installed-slicers-after.png" width="294" alt="Seletor nativo de um 3MF sintético, com OrcaSlicer, Bambu Studio e Snapmaker Orca instalados no Mac de teste">
</p>

*Seletor nativo com sample sintético. A lista corresponde aos fatiadores instalados no Mac de teste.*

## Renderização local e privacidade

As thumbnails usam a geometria e as cores dos filamentos, renderizadas com SceneKit e Metal.
Câmera e iluminação são definidas pelo código. Nenhum modelo de IA participa. Em verificações locais,
o mesmo sample produziu PNGs com hashes iguais. Não há garantia de pixels idênticos entre versões
de macOS ou GPUs diferentes.

O app mantém escolhas, catálogo e previews na pasta Application Support do usuário. O indexador
opcional só lê arquivos visíveis ao Spotlight e permitidos pelo macOS. O aplicativo não tem cliente
de rede nem configuração de credenciais.

## Perguntas frequentes

**Ele mexe nos meus arquivos?** Só num atributo estendido com a decisão. O conteúdo do 3MF continua
idêntico, byte a byte.

**O preview atualiza depois que edito o projeto?** Salvar invalida o preview gerado. Na próxima solicitação,
o Finder renderiza a geometria atual da primeira chapa se não houver imagem indexada pronta; o indexador
opcional a prepara na próxima passada ociosa. Apenas o fallback de erro/projeto grande pode manter um
screenshot antigo do fatiador. Fechar sem salvar não muda nada.

**Precisa de permissão especial?** Abrir um arquivo e gerar seu preview não exige Acessibilidade,
Gravação de Tela ou Acesso Total ao Disco. O indexador opcional pode exigir sua aprovação para
atividade em background e acesso a pastas protegidas.

**Manda dados para algum lugar?** Não. Roteamento e previews são executados no seu Mac.
Não exigem serviço de rede, modelo de IA, API key nem conta.

**Ele roda em background?** Só se você ligar o indexador, e mesmo assim só com o Mac ocioso e na tomada.

## Roadmap

- [x] OrcaSlicer oficial como padrão, separado do Snapmaker Orca
- [ ] Padrões prontos para PrusaSlicer, Elegoo Slicer e Creality Print (hoje: *Outro app…* ou `--map`)
- [ ] Janela de configurações para os mapeamentos impressora → fatiador
- [ ] Largura de extrusão (fitas) no preview de G-code
- [ ] Release notarizado

Ideias, impressoras que roteiam errado e PRs são bem-vindos: [CONTRIBUTING.md](CONTRIBUTING.md).

## Aviso

Sem afiliação, endosso ou patrocínio da Bambu Lab ou da Snapmaker. Bambu Studio, Snapmaker Orca e
seus ícones são marcas dos respectivos donos, mostrados só para descrever compatibilidade.

## Licença

[MIT](LICENSE) © Gilberto Moraes ([@MoraesGil](https://github.com/MoraesGil))
