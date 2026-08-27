#!/usr/bin/env bash
#
# package.sh - monta a pasta nzportable/ pronta para jogar, SEM COMPILAR NADA.
#
# Precisa apenas de: bash, curl (ou wget), unzip e sha256sum.
# Nao precisa de compilador, nao precisa de Python, nao precisa de toolchain.
#
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$ROOT/lib.sh"
# shellcheck source=sources.env
. "$ROOT/sources.env"

CACHE="$ROOT/.cache"
DIST="$ROOT/dist"
OUT="$ROOT/nzportable"

USE_LOCAL=0
RELEASE_TAG=""
REFRESH_ASSETS=0
FORCE=0

usage() {
	cat <<'EOF'
Uso: ./package.sh [opcoes]

Monta a pasta nzportable/ pronta para copiar para o PSP ou o PPSSPP.
Baixa os dados do jogo da nightly oficial do nzp-team e troca apenas o
EBOOT.PBP e o nzp/progs.dat pelos desta build com AdHoc.

Opcoes:
  --local              usa os arquivos de dist/ gerados pelo ./build.sh
                       (em vez de baixar da release deste repositorio)
  --tag TAG            baixa os artefatos desta tag (padrao: release mais recente)
  --out DIR            pasta de destino (padrao: ./nzportable)
  --refresh-assets     rebaixa a nightly do nzp-team mesmo havendo cache
  --force              remonta a pasta mesmo que ja esteja atualizada
  -h, --help           esta ajuda

Depois de rodar, copie a pasta para:
  PSP real           ->  PSP/GAME/
  PPSSPP (Android)   ->  /sdcard/PSP/GAME/
EOF
}

while [ $# -gt 0 ]; do
	case "$1" in
		--local) USE_LOCAL=1; shift ;;
		--tag) RELEASE_TAG="${2:?--tag precisa de um valor}"; shift 2 ;;
		--out) OUT="$(cd -- "$(dirname -- "${2:?--out precisa de um valor}")" && pwd)/$(basename -- "$2")"; shift 2 ;;
		--refresh-assets) REFRESH_ASSETS=1; shift ;;
		--force) FORCE=1; shift ;;
		-h|--help) usage; exit 0 ;;
		*) die "opcao desconhecida: $1" "Rode ./package.sh --help" ;;
	esac
done

have unzip || die "unzip nao encontrado." \
	"Instale com:" \
	"  sudo apt install unzip     (Debian/Ubuntu)" \
	"  sudo pacman -S unzip       (Arch)"
pick_downloader

# ---------------------------------------------------------------------------
# 1. EBOOT.PBP + progs.dat
# ---------------------------------------------------------------------------
step "[1/5] Obtendo EBOOT.PBP e progs.dat"

if [ "$USE_LOCAL" -eq 1 ]; then
	SRC_EBOOT="$DIST/EBOOT.PBP"
	SRC_PROGS="$DIST/progs.dat"
	[ -f "$SRC_EBOOT" ] && [ -f "$SRC_PROGS" ] || die \
		"nao achei os arquivos locais em dist/." \
		"faltando: ${SRC_EBOOT##"$ROOT"/} e/ou ${SRC_PROGS##"$ROOT"/}" \
		"" \
		"Rode ./build.sh primeiro, ou tire o --local para baixar da release."
	info "origem: dist/ (build local)"
	if [ -f "$DIST/SHA256SUMS.txt" ]; then
		( cd "$DIST" && if have sha256sum; then sha256sum -c --quiet SHA256SUMS.txt
		  else shasum -a 256 -c SHA256SUMS.txt >/dev/null; fi ) \
			|| die "os arquivos em dist/ nao batem com dist/SHA256SUMS.txt." \
			       "Rode ./build.sh de novo."
		info "checksum ok: dist/SHA256SUMS.txt"
	else
		warn "dist/SHA256SUMS.txt ausente; seguindo sem conferir."
	fi
else
	if [ -z "$RELEASE_TAG" ]; then
		info "consultando a release mais recente de $RELEASE_REPO..."
		RELEASE_TAG="$(gh_latest_tag "$RELEASE_REPO" || true)"
		[ -n "$RELEASE_TAG" ] || die \
			"nao achei nenhuma release em $RELEASE_REPO." \
			"" \
			"Se ainda nao existe release publicada, compile do zero:" \
			"  ./build.sh && ./package.sh --local"
	fi
	info "release: $RELEASE_TAG"
	RDIR="$CACHE/release/$RELEASE_TAG"
	mkdir -p "$RDIR"
	for f in EBOOT.PBP progs.dat SHA256SUMS.txt; do
		if [ -f "$RDIR/$f" ] && [ "$REFRESH_ASSETS" -eq 0 ]; then
			info "em cache: $f"
		else
			info "baixando $f..."
			fetch_file "$(gh_asset_url "$RELEASE_REPO" "$RELEASE_TAG" "$f")" "$RDIR/$f"
		fi
	done
	( cd "$RDIR" && if have sha256sum; then sha256sum -c --quiet SHA256SUMS.txt
	  else shasum -a 256 -c SHA256SUMS.txt >/dev/null; fi ) \
		|| die "os artefatos baixados nao batem com o SHA256SUMS.txt da release." \
		       "Apague $RDIR e rode de novo."
	info "checksum ok: SHA256SUMS.txt da release"
	SRC_EBOOT="$RDIR/EBOOT.PBP"
	SRC_PROGS="$RDIR/progs.dat"
fi

EBOOT_SHA="$(sha256_of "$SRC_EBOOT")"
PROGS_SHA="$(sha256_of "$SRC_PROGS")"
info "EBOOT.PBP  $EBOOT_SHA"
info "progs.dat  $PROGS_SHA"

# ---------------------------------------------------------------------------
# 2. dados do jogo (nightly oficial do nzp-team)
# ---------------------------------------------------------------------------
step "[2/5] Dados do jogo: nightly oficial do nzp-team"

GDIR="$CACHE/gamedata"
ZIP="$GDIR/$GAMEDATA_ASSET"
ZIP_SHA_FILE="$ZIP.sha256"
ZIP_VER_FILE="$ZIP.version"
mkdir -p "$GDIR"

download_gamedata() {
	info "baixando $GAMEDATA_ASSET de $GAMEDATA_REPO@$GAMEDATA_TAG (~100 MB)..."
	fetch_file "$(gh_asset_url "$GAMEDATA_REPO" "$GAMEDATA_TAG" "$GAMEDATA_ASSET")" "$ZIP"
	sha256_of "$ZIP" > "$ZIP_SHA_FILE"
	fetch_stdout "$(gh_asset_url "$GAMEDATA_REPO" "$GAMEDATA_TAG" "$GAMEDATA_VERSION_ASSET")" \
		> "$ZIP_VER_FILE" 2>/dev/null || echo "desconhecida" > "$ZIP_VER_FILE"
}

if [ -f "$ZIP" ] && [ "$REFRESH_ASSETS" -eq 0 ]; then
	# Cache local vence: a tag "nightly" e rolante e rebaixar sozinho
	# trocaria os assets do usuario sem ele pedir.
	info "usando o cache local (nao rebaixa a nightly sozinho)"
	info "arquivo: ${ZIP##"$ROOT"/}"
	info "versao:  $(cat "$ZIP_VER_FILE" 2>/dev/null || echo desconhecida)"
	if [ -f "$ZIP_SHA_FILE" ]; then
		expect_sha "$ZIP" "$(cat "$ZIP_SHA_FILE")" "nzportable-psp.zip (cache)"
	else
		info "sem checksum gravado para o cache; gravando agora"
		sha256_of "$ZIP" > "$ZIP_SHA_FILE"
	fi
	info "para atualizar a nightly: ./package.sh --refresh-assets"
else
	if [ "$REFRESH_ASSETS" -eq 1 ] && [ -f "$ZIP" ]; then info "--refresh-assets: rebaixando"; fi
	download_gamedata
	info "versao:  $(cat "$ZIP_VER_FILE")"
fi

unzip -tqq "$ZIP" >/dev/null 2>&1 || die \
	"o zip da nightly esta corrompido: ${ZIP##"$ROOT"/}" \
	"Apague o arquivo e rode ./package.sh --refresh-assets"
info "integridade do zip ok"

GAMEDATA_SHA="$(cat "$ZIP_SHA_FILE")"

# ---------------------------------------------------------------------------
# 3. ja esta pronto?
# ---------------------------------------------------------------------------
STAMP="$OUT/.nzp-adhoc-package"
STAMP_NOW="gamedata=$GAMEDATA_SHA
eboot=$EBOOT_SHA
progs=$PROGS_SHA"

if [ "$FORCE" -eq 0 ] && [ -f "$STAMP" ] && [ "$(cat "$STAMP")" = "$STAMP_NOW" ]; then
	step "[3/5] A pasta ja esta montada e atualizada"
	info "${OUT##"$ROOT"/}  (nada a fazer)"
	step "Pronto."
	info "para remontar do zero: ./package.sh --force"
	exit 0
fi

# ---------------------------------------------------------------------------
# 4. extrair
# ---------------------------------------------------------------------------
step "[3/5] Extraindo os dados do jogo"

TMP="$CACHE/extract.tmp"
rm -rf "$TMP"
mkdir -p "$TMP"
unzip -q -o "$ZIP" -d "$TMP"
[ -d "$TMP/nzportable/nzp" ] || die \
	"o zip da nightly nao tem a pasta nzportable/nzp esperada." \
	"O layout da nightly do nzp-team pode ter mudado."
info "extraido"

step "[4/5] Trocando EBOOT.PBP e nzp/progs.dat pelos desta build"
cp -f "$SRC_EBOOT" "$TMP/nzportable/EBOOT.PBP"
cp -f "$SRC_PROGS" "$TMP/nzportable/nzp/progs.dat"

# Confere que o que ficou na pasta e exatamente o que devia ficar.
expect_sha "$TMP/nzportable/EBOOT.PBP" "$EBOOT_SHA" "EBOOT.PBP instalado"
expect_sha "$TMP/nzportable/nzp/progs.dat" "$PROGS_SHA" "progs.dat instalado"
printf '%s\n' "$STAMP_NOW" > "$TMP/nzportable/.nzp-adhoc-package"

# ---------------------------------------------------------------------------
# 5. entregar
# ---------------------------------------------------------------------------
step "[5/5] Montando ${OUT##"$ROOT"/}"
rm -rf "$OUT.old"
if [ -e "$OUT" ]; then mv -f "$OUT" "$OUT.old"; fi
mkdir -p "$(dirname "$OUT")"
mv -f "$TMP/nzportable" "$OUT"
rm -rf "$OUT.old" "$TMP"

SIZE="$(du -sh "$OUT" | cut -f1)"

cat <<EOF

${C_G}Pronto.${C_0} Pasta montada: ${C_B}$OUT${C_0} ($SIZE)

  EBOOT.PBP        $EBOOT_SHA
  nzp/progs.dat    $PROGS_SHA
  dados do jogo    nightly $(cat "$ZIP_VER_FILE" 2>/dev/null || echo '?') (nzp-team)

Copie a pasta inteira para:

  PSP real          PSP/GAME/nzportable
  PPSSPP Android    /sdcard/PSP/GAME/nzportable

Exemplos:
  cp -r "$OUT" /media/\$USER/PSP/PSP/GAME/
  adb push "$OUT" /sdcard/PSP/GAME/

Antes de jogar em rede, confira a secao de configuracao do PPSSPP no README.
EOF
