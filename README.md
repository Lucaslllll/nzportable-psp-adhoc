# NZ:P PSP AdHoc

Build da comunidade do **Nazi Zombies: Portable 2.x para PSP** com o
**multiplayer AdHoc (coop) reativado**.

O NZ:P 2.x não tem multiplayer: o menu `COOPERATIVE` existe mas está
desabilitado, e o driver AdHoc do engine estava dormente no código. Esta build
reativa esse caminho — menu de host/join, descoberta de sala por AdHoc,
espectador que nasce na virada de rodada — e funciona tanto em **LAN** quanto
pela **internet** (via servidor de relay do PPSSPP).

> **Fork não-oficial.** O jogo é do [nzp-team](https://github.com/nzp-team/nzportable)
> e todo o crédito pelo NZ:P é deles. Este repositório não é mantido nem
> endossado pelo nzp-team, e **não redistribui os dados do jogo** — eles são
> baixados da nightly oficial na sua máquina, na hora de montar a pasta.

Este repositório é só a **cola**: dois scripts, as fontes fixadas em commits
exatos e o CI que gera os binários. O código de verdade está nos forks:

| | repositório | branch | commit |
|---|---|---|---|
| engine | [Lucaslllll/vril-engine](https://github.com/Lucaslllll/vril-engine) | `feature/psp-adhoc-multiplayer` | [`a99d067d`](https://github.com/Lucaslllll/vril-engine/commit/a99d067d9abb9509795c0243dc54807c43e1d26c) |
| QuakeC | [Lucaslllll/quakec](https://github.com/Lucaslllll/quakec) | `feature/standard-coop-spawn` | [`bc4c3439`](https://github.com/Lucaslllll/quakec/commit/bc4c34397a7aec040c86bf22b8a1fab309def126) |

---

## Só quero jogar (recomendado)

Um comando. **Não precisa de compilador, nem de Python, nem de toolchain** —
só `bash`, `curl` (ou `wget`) e `unzip`.

```bash
git clone https://github.com/Lucaslllll/nzportable-psp-adhoc
cd nzportable-psp-adhoc
./package.sh
```

O `package.sh` faz o seguinte:

1. baixa o `EBOOT.PBP` e o `progs.dat` da [release mais recente](https://github.com/Lucaslllll/nzportable-psp-adhoc/releases/latest)
   deste repositório (~2,2 MB) e confere os checksums;
2. baixa o `nzportable-psp.zip` da
   [nightly oficial do nzp-team](https://github.com/nzp-team/nzportable/releases/tag/nightly)
   (~100 MB) e extrai;
3. troca **apenas** o `EBOOT.PBP` e o `nzp/progs.dat` pelos da build com AdHoc;
4. deixa a pasta `nzportable/` pronta.

No fim, copie a pasta inteira para:

| onde você joga | destino |
|---|---|
| PSP real | `PSP/GAME/nzportable` |
| PPSSPP Android | `/sdcard/PSP/GAME/nzportable` |
| PPSSPP desktop | qualquer pasta; abra o `EBOOT.PBP` |

```bash
cp -r nzportable /media/$USER/PSP/PSP/GAME/      # PSP real
adb push nzportable /sdcard/PSP/GAME/            # Android
```

Rodar de novo é seguro: se nada mudou, o script não faz nada. Ele também **não
rebaixa a nightly sozinho** — o `nightly` é uma tag rolante, então o cache local
vence. Para atualizar os dados do jogo de propósito:

```bash
./package.sh --refresh-assets
```

Outras opções: `./package.sh --help`.

**Os dois jogadores precisam do mesmo `EBOOT.PBP` e do mesmo `progs.dat`.**
Versões diferentes não se enxergam.

---

## Configuração do PPSSPP

Isto é metade do trabalho para o coop funcionar. Leia antes de dizer que não
funciona.

### ⚠️ Em homebrew, só vale o CONFIG GLOBAL

O PPSSPP tem configuração por jogo, **mas ela não é aplicada a homebrew**. O
carregador de ISO/CSO chama `LoadGameConfig()`; o `Load_PSP_ELF_PBP` — o caminho
de qualquer `EBOOT.PBP`, que é o nosso caso — **nunca chama**. O arquivo
`PSP/SYSTEM/<ID>_ppsspp.ini` é simplesmente ignorado em tempo de execução.

O detalhe cruel: pela **lista de jogos** o PPSSPP deixa você abrir as
configurações do NZ:P, mexer na rede e salvar — ele grava direitinho no arquivo
por jogo — e na hora de rodar não lê nada disso. As opções *parecem* ter sido
salvas e não fazem efeito nenhum.

> **Regra: configure a rede pelo menu principal do PPSSPP
> (Configurações → Rede), com o jogo fechado.**
> Se for editar arquivo na mão, edite o `ppsspp.ini` **global**.

Sintoma de quando isso morde: `COULD NOT START ADHOC.` no jogo, e
`Socket error (110) when connecting to AdhocServer` no log.

### Em todos os aparelhos

| Configuração | Valor |
|---|---|
| Habilitar rede/WLAN | ✅ ligado |
| **Port offset** | **10000 — o mesmo em todos os aparelhos** |
| **MAC address** | **diferente em cada aparelho** |

### Jogando pela internet (relay)

Serve para jogar com quem não está na sua rede. Ninguém precisa abrir porta no
roteador: o PPSSPP manda todo o tráfego do jogo para o servidor de relay, que
reencaminha para o outro jogador.

| Configuração | Valor |
|---|---|
| Servidor Ad Hoc | um servidor de relay, ex. `brazil-01.sprawl-relay.link` |
| Servidor Ad Hoc embutido | ❌ **desligado** |
| Try to use server-provided packet relay | **Auto** |

O `Auto` só sabe que aquele servidor é de relay se ele estiver na **lista de
servidores** — a lista embutida no PPSSPP, ou a baixada de `metadata.ppsspp.org`
(que fica em cache e não expira na leitura). O `brazil-01.sprawl-relay.link` só
entrou na lista embutida a partir do **PPSSPP 1.20.4**.

- **PPSSPP 1.20.4 ou mais novo** → funciona direto.
- **Mais antigo** → abra a tela de Rede uma vez com internet para baixar a lista
  (fica em cache). **O ideal é atualizar o PPSSPP.**

Cuidado com **assimetria**: se um aparelho conhece o servidor e o outro não, um
fica em relay e o outro em P2P, e eles nunca se enxergam — mesmo com todo o
resto certo.

### Jogando em LAN ou VPN

| Configuração | Valor |
|---|---|
| Servidor Ad Hoc | o **IP da máquina** que roda o servidor embutido |
| Servidor Ad Hoc embutido | ✅ **ligado — só nessa máquina** (e vale pelo global) |
| Try to use server-provided packet relay | **Auto** |

**Não deixe o relay em `Yes` para LAN.** O `Yes` força relay para *qualquer*
servidor: apontando para um IP de máquina, o PPSSPP tenta falar postoffice na
porta **27313** dela, não tem nada ouvindo, e depois de 15 s ele desativa o relay
com um aviso na tela — **sem voltar para P2P**. AdHoc morre ali. (E se o `Yes`
estiver no config global, ele vaza para todos os seus outros jogos.)

Deixar em `Auto` sempre é o certo: ele escolhe relay para servidor de relay
conhecido e P2P para IP de LAN/VPN. Assim, trocar entre internet e LAN é só
mudar o endereço do servidor.

### Diagnóstico rápido

Qual transporte está no ar (funciona no PC e no celular via `adb shell`):

```bash
ss -tn | grep -E '27312|27313'
```

- apareceu **27313** → está em modo **relay**;
- só **27312** → está em **P2P**;
- nada → o AdHoc não subiu.

E para checar se o servidor embutido realmente subiu na máquina host:

```bash
ss -tlnp | grep 27312     # sem ninguém escutando = não subiu
```

---

## Como jogar

1. **Host:** `COOPERATIVE → HOST GAME →` escolha o mapa `→ START GAME`.
2. **Cliente:** `COOPERATIVE → JOIN GAME →` a sala aparece como
   `nome (mapa) n/4 →` aperte **X**.

Detalhes que economizam tempo:

- **Se aparecer `COULD NOT START ADHOC.`, aperte de novo.** Falha comum na
  primeira tentativa (o servidor leva 1–2 s para subir na primeira ativação).
- **O movimento no NZ:P PSP é nos BOTÕES DE AÇÃO** (triângulo / X / quadrado /
  círculo). O analógico só olha em volta. Isto não é bug e pega todo mundo de
  primeira viagem.
- Entrar no meio da rodada te faz **espectador**; você nasce na rodada seguinte,
  com arma e 500 pontos. É o comportamento correto.

### Limitações conhecidas

- O cliente não vê o **nome da arma** no HUD (só o contador de munição).
- A mira ADS do cliente fica centralizada (o offset por arma não é replicado).
- Música de easter egg toca só no host.
- Se a conexão cair, o cliente volta ao menu principal. Se a tela ficar preta com
  a música do menu, aperte X/O.
- **v1 e 2.x não se enxergam**, de propósito (grupo AdHoc `nzp2`, protocolo 16).

---

## Compilando do zero

Só se você quiser mexer no código. Para jogar, use o
[caminho de cima](#só-quero-jogar-recomendado).

```bash
./build.sh
./package.sh --local
```

O `build.sh`:

1. **baixa o toolchain PSP** de [pspdev/pspdev](https://github.com/pspdev/pspdev/releases)
   para `toolchain/pspdev`, se você ainda não tiver um;
2. **clona os dois forks** nos commits fixados em [`sources.env`](sources.env),
   dentro de `.work/`;
3. compila o engine: `make -f Makefile.psp WERROR=1 -j$(nproc)`
   → `build/psp/bin/EBOOT.PBP`;
4. compila o QuakeC com o `tools/qc-compiler-gnu.sh` do próprio repo `quakec`,
   num venv Python criado em `toolchain/qcvenv`
   → `build/standard/progs.dat`;
5. copia os dois para `dist/` junto com `dist/SHA256SUMS.txt`.

Depois, `./package.sh --local` monta a pasta `nzportable/` usando o que está em
`dist/` em vez de baixar da release.

Opções: `./build.sh --help` (tem `--only engine`, `--only quakec`, `--clean`, `-j N`).

### ⚠️ Toolchain: a pegadinha da glibc

Releases do pspdev mais novas que ~`v20250801` são compiladas em **Debian 13** e
abortam com **`GLIBC_2.38 not found`** em quem tem glibc mais antiga (Debian 12 =
glibc 2.36).

O `build.sh` detecta isso: se a sua glibc for menor que 2.38, ele usa a release
**`v20250701`** (psp-gcc 15.1.1), que já traz `libpspmath` e as bibliotecas de
AdHoc. Se você já tem um toolchain que funciona, use o seu:

```bash
PSPDEV=/caminho/do/pspdev ./build.sh
```

### ⚠️ QuakeC: a pegadinha do pandas

O `bin/qc_hash_generator.py` do repo `quakec` precisa de **`pandas==1.5.3`**. O
`requirements.txt` oficial do nzp-team pede `pandas==2.1.4`, mas no pandas 2.x o
acesso a `DataFrame.values` mudou de semântica (passou a devolver uma cópia
consolidada em vez de iterar as linhas como o script espera) e a geração da
`hash_table.qc` quebra.

Os pins estão em [`requirements-qc.txt`](requirements-qc.txt). O `pandas 1.5.3`
só tem wheel pronta até o **Python 3.11** — se o seu `python3` for 3.12+, crie o
venv com um 3.11:

```bash
rm -rf toolchain/qcvenv
python3.11 -m venv toolchain/qcvenv
./build.sh --only quakec
```

---

## Estado dos testes

Testado em máquina limpa (Debian 12, glibc 2.36), simulando alguém que só clonou
o repositório: `env -i`, `HOME` novo, `PATH` mínimo, sem `PSPDEV`, sem toolchain,
sem venv, sem token e sem cache nenhum.

**O caminho recomendado**, exatamente o comando do topo deste README, exit 0:
achou a release `v1.0.0` pela API, baixou os três assets, **conferiu os checksums
contra o `SHA256SUMS.txt` da própria release**, baixou a nightly do nzp-team e
montou `nzportable/` (132 MB). Os outros **1169 arquivos são exatamente os do zip
do nzp-team** — nenhum a mais, nenhum a menos, nenhum alterado; só o `EBOOT.PBP`
e o `nzp/progs.dat` foram trocados.

**Compilando do zero** — `./build.sh && ./package.sh --local`, exit 0: baixou o
toolchain, detectou a glibc antiga e caiu para o `pspdev v20250701`, clonou os
dois forks nos commits fixados (conferido com `git rev-parse HEAD`) e gerou
`EBOOT.PBP` (1,5 MB) e `progs.dat` (764 KB) com os checksums. O `progs.dat`
compilado localmente saiu byte-a-byte igual ao publicado na release.

**CI** — todo push e PR compila; a tag `v*` publica. Exercitado inteiro, o job de
release incluído.

### O jogo montado roda

A pasta gerada pelo caminho recomendado — binários da release `v1.0.0` mais os
assets do nzp-team — foi aberta no PPSSPP 1.20.2 e jogada até dentro do mapa:

| tela | o que apareceu |
|---|---|
| MAIN MENU | versão `2.0.0-indev+20260826075151`, **COOPERATIVE ativo** (não mais cinza) |
| COOPERATIVE | `HOST GAME` / `JOIN GAME` — *"Create an AdHoc Game for nearby PSPs."* |
| SELECT MAP | lista completa de mapas; PPSSPP anunciou **"Multiplayer do Ad Hoc: Modo P2P"** |
| PRE-GAME | lobby de host com contagem *"Game Starting In.."* |
| em jogo | Nacht der Untoten carregado, HUD com 500 pontos e a Colt na mão |

E o log do PPSSPP confirma que o AdHoc subiu de verdade, com o comportamento
esperado desta build:

```
sceNetAdhocctlConnect(nzp2)
AdhocServer: ... joined ... group nzp2
sceNetAdhocPdpCreate(34:f2:25:2e:7c:c9, 26001, 8192, 0)
sceNetAdhocPdpCreate(34:f2:25:2e:7c:c9, 26000, 8192, 0)
```

O grupo é `nzp2` (é o que isola esta build da v1) e os sockets pedem **porta
explícita** — 26000 e 26001 — em vez de porta 0, que é a correção que faz o modo
relay do PPSSPP funcionar.

### Reprodutibilidade

Dois builds do **mesmo commit** não dão o mesmo checksum: o engine compila
`__DATE__`/`__TIME__` no banner de versão e o `fteqcc` grava a data dentro do
`progs.dat`. Comparando dois `progs.dat` do mesmo commit com três dias de
diferença, a divergência era de **exatamente 1 byte** — o dígito da data. Builds
do mesmo dia saem idênticos. É por isso que os checksums vêm da release e são
conferidos contra ela, em vez de recalculados localmente.

## Releases e distribuição

As releases contêm **apenas** `EBOOT.PBP`, `progs.dat` e `SHA256SUMS.txt`
(~2,2 MB no total). **Os dados do jogo não estão aqui e não estão nas releases**
— eles são do nzp-team, e o `package.sh` os baixa da nightly oficial na máquina
de quem vai jogar.

Os binários das releases são gerados pelo **CI** (GitHub Actions), não na minha
máquina: o engine é compilado na imagem `pspdev/pspdev` e o QuakeC num runner
Ubuntu com Python 3.11. Todo push e PR valida que compila; uma tag `v*` publica a
release. Veja [`.github/workflows/build.yml`](.github/workflows/build.yml).

## Licença

O engine é derivado do **Quake**, então este projeto é **GPL-2.0** — veja
[`LICENSE`](LICENSE).

O código-fonte correspondente aos binários das releases são os dois forks, nos
commits fixados em [`sources.env`](sources.env):

- engine: <https://github.com/Lucaslllll/vril-engine> `feature/psp-adhoc-multiplayer` @ `a99d067d9abb9509795c0243dc54807c43e1d26c`
- QuakeC: <https://github.com/Lucaslllll/quakec> `feature/standard-coop-spawn` @ `bc4c34397a7aec040c86bf22b8a1fab309def126`

Os dados do jogo (modelos, texturas, sons, mapas) são do
[nzp-team](https://github.com/nzp-team/nzportable) e mantêm as licenças e
atribuições que vêm dentro do próprio pacote (`nzp/licenses/`). Nada disso é
redistribuído por este repositório.

---
---

# English

Community build of **Nazi Zombies: Portable 2.x for PSP** with **AdHoc
multiplayer (co-op) re-enabled**.

NZ:P 2.x ships with no multiplayer — the `COOPERATIVE` menu entry exists but is
greyed out, and the engine's AdHoc driver was dormant in the source. This build
wakes that path up: host/join menu, AdHoc game discovery, spectator that spawns
on the next round. It works on **LAN** and over the **internet** (through a
PPSSPP relay server).

> **Unofficial fork.** The game is by the
> [nzp-team](https://github.com/nzp-team/nzportable) and all credit for NZ:P goes
> to them. This repository is not maintained or endorsed by the nzp-team, and it
> **does not redistribute the game data** — that is downloaded from the official
> nightly on your own machine at packaging time.

This repo is only the glue: two scripts, sources pinned to exact commits, and the
CI that produces the binaries. The actual code lives in the two forks listed in
[`sources.env`](sources.env).

## Just play (recommended)

One command. **No compiler, no Python, no toolchain** — only `bash`, `curl` (or
`wget`) and `unzip`.

```bash
git clone https://github.com/Lucaslllll/nzportable-psp-adhoc
cd nzportable-psp-adhoc
./package.sh
```

It downloads `EBOOT.PBP` + `progs.dat` from this repo's latest release (~2.2 MB,
checksum-verified), downloads `nzportable-psp.zip` from the official nzp-team
nightly (~100 MB), swaps **only** those two files in, and leaves a ready
`nzportable/` folder. Copy the whole folder to `PSP/GAME/` on a real PSP, or
`/sdcard/PSP/GAME/` for PPSSPP on Android.

Re-running is safe and does nothing if nothing changed. It will **not** silently
re-download the rolling nightly — use `./package.sh --refresh-assets` when you
actually want newer game data.

**Both players need the same `EBOOT.PBP` and `progs.dat`.**

## PPSSPP setup

This is half the work. The short version:

- **Only the GLOBAL config applies to homebrew.** PPSSPP's per-game config is
  loaded by the ISO/CSO loader, but `Load_PSP_ELF_PBP` — the path every
  `EBOOT.PBP` takes — never calls `LoadGameConfig()`. Editing the network
  settings from the game list *saves* them and then silently ignores them.
  **Set networking from the main menu, with the game closed.**
- **Every device:** same **Port offset** (`10000`), **different MAC address**.
- **Internet (relay):** Ad Hoc server = a relay server (e.g.
  `brazil-01.sprawl-relay.link`), built-in Ad Hoc server **off**, and *"Try to
  use server-provided packet relay"* = **Auto**. Auto only recognises a relay
  server if it is in PPSSPP's server list — `brazil-01.sprawl-relay.link` is in
  the bundled list from **1.20.4** on; on older builds, open the Network screen
  once while online so the list gets cached. Best is to update PPSSPP. Watch out
  for asymmetry: if one device knows the server and the other doesn't, one runs
  relay and the other P2P and they never see each other.
- **LAN/VPN:** Ad Hoc server = the **IP of the machine** running the built-in
  server, built-in server **on** on that machine, relay still on **Auto**. Do
  **not** pin relay to `Yes` here: it forces relay for any server, tries port
  **27313** on that machine, and after 15 s disables relay *without falling back
  to P2P*.
- **Quick check:** `ss -tn | grep -E '27312|27313'` — 27313 present means relay
  mode, only 27312 means P2P.

## How to play

`COOPERATIVE → HOST GAME` / `JOIN GAME`.

- If you get **`COULD NOT START ADHOC.`, press it again** — common on the first
  attempt.
- **Movement in NZ:P on PSP is on the ACTION BUTTONS** (triangle/X/square/circle);
  the analog stick only looks around.
- Joining mid-round makes you a spectator; you spawn on the next round.

## Building from source

```bash
./build.sh          # downloads the PSP toolchain, clones both pinned forks, builds
./package.sh --local
```

Two traps `build.sh` handles for you:

- **glibc:** pspdev releases newer than ~`v20250801` are built on Debian 13 and
  die with `GLIBC_2.38 not found` on older systems. If your glibc is below 2.38,
  the script falls back to `v20250701`. Or bring your own:
  `PSPDEV=/path/to/pspdev ./build.sh`.
- **pandas:** `qc_hash_generator.py` needs **`pandas==1.5.3`**; the upstream
  requirements pin `2.1.4`, and pandas 2.x changed `DataFrame.values` semantics,
  which breaks hash table generation. Pins live in
  [`requirements-qc.txt`](requirements-qc.txt) (wheels only up to Python 3.11).

## Test status

Verified on a clean machine (Debian 12, glibc 2.36) with `env -i`, a fresh
`HOME`, a minimal `PATH`, no `PSPDEV`, no toolchain, no token and no cache:

- **the recommended path** — the exact one-liner above — resolved release
  `v1.0.0`, verified the assets against the release's own `SHA256SUMS.txt`,
  pulled the nzp-team nightly and assembled `nzportable/`. All 1169 other files
  match the nzp-team zip exactly; only `EBOOT.PBP` and `nzp/progs.dat` differ.
- **building from source** — `./build.sh && ./package.sh --local` fell back to
  `pspdev v20250701` for the old glibc, built both forks at the pinned commits,
  and produced a `progs.dat` byte-identical to the released one.
- **the assembled game runs** — booted in PPSSPP 1.20.2 through
  `COOPERATIVE → HOST GAME → SELECT MAP` into Nacht der Untoten, with
  `sceNetAdhocctlConnect(nzp2)` and explicit AdHoc ports 26000/26001 in the log.

Note on reproducibility: the engine bakes `__DATE__`/`__TIME__` into its version
banner and fteqcc stamps the compile date into `progs.dat`, so two builds of the
same commit on different days differ — by exactly one byte, the date digit.

## Distribution and licence

Releases contain **only** `EBOOT.PBP`, `progs.dat` and `SHA256SUMS.txt`. Game
data is never versioned here nor attached to releases — it belongs to the
nzp-team and is fetched by `package.sh` on the user's machine. Release binaries
are produced by CI, not locally.

The engine is Quake-derived, so this project is **GPL-2.0** (see
[`LICENSE`](LICENSE)). The corresponding source for the release binaries is the
two forks at the commits pinned in [`sources.env`](sources.env). Game assets keep
their own licences and attributions, shipped inside the package under
`nzp/licenses/`.
