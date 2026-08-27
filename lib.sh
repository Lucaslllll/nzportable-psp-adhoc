#!/usr/bin/env bash
# Funcoes compartilhadas por build.sh e package.sh.
# Shared helpers for build.sh and package.sh.

# --- saida ---------------------------------------------------------------
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
	C_B=$'\033[1m'; C_R=$'\033[31m'; C_G=$'\033[32m'; C_Y=$'\033[33m'; C_0=$'\033[0m'
else
	C_B=''; C_R=''; C_G=''; C_Y=''; C_0=''
fi

step() { printf '%s==>%s %s%s\n' "$C_G" "$C_0" "$C_B" "$*$C_0"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '%swarn:%s %s\n' "$C_Y" "$C_0" "$*" >&2; }
die() {
	printf '\n%serro:%s %s\n' "$C_R" "$C_0" "$1" >&2
	shift
	for line in "$@"; do printf '       %s\n' "$line" >&2; done
	exit 1
}

have() { command -v "$1" >/dev/null 2>&1; }

# --- download ------------------------------------------------------------
# Escolhe curl ou wget uma vez.
DOWNLOADER=""
pick_downloader() {
	[ -n "$DOWNLOADER" ] && return 0
	if have curl; then DOWNLOADER=curl
	elif have wget; then DOWNLOADER=wget
	else
		die "nem curl nem wget encontrados." \
		    "Instale um dos dois, por exemplo:" \
		    "  sudo apt install curl      (Debian/Ubuntu)" \
		    "  sudo pacman -S curl        (Arch)"
	fi
}

# fetch_stdout <url> -> imprime o corpo na saida padrao
fetch_stdout() {
	pick_downloader
	local -a auth=()
	if [ "$DOWNLOADER" = curl ]; then
		if [ -n "${GITHUB_TOKEN:-}" ]; then auth=(-H "Authorization: Bearer $GITHUB_TOKEN"); fi
		curl -fsSL --retry 3 --retry-delay 2 "${auth[@]}" "$1"
	else
		if [ -n "${GITHUB_TOKEN:-}" ]; then auth=(--header "Authorization: Bearer $GITHUB_TOKEN"); fi
		wget -qO- --tries=3 "${auth[@]}" "$1"
	fi
}

# fetch_file <url> <destino>  (atomico: baixa em .part e move no final)
fetch_file() {
	local url="$1" out="$2"
	local -a auth=()
	pick_downloader
	mkdir -p "$(dirname "$out")"
	rm -f "$out.part"
	if [ "$DOWNLOADER" = curl ]; then
		if [ -n "${GITHUB_TOKEN:-}" ]; then auth=(-H "Authorization: Bearer $GITHUB_TOKEN"); fi
		curl -fL --retry 3 --retry-delay 2 --progress-bar "${auth[@]}" \
			-o "$out.part" "$url" \
			|| die "falha ao baixar $url"
	else
		if [ -n "${GITHUB_TOKEN:-}" ]; then auth=(--header "Authorization: Bearer $GITHUB_TOKEN"); fi
		wget --tries=3 -q --show-progress "${auth[@]}" \
			-O "$out.part" "$url" \
			|| die "falha ao baixar $url"
	fi
	mv -f "$out.part" "$out"
}

# --- checksums -----------------------------------------------------------
sha256_of() {
	if have sha256sum; then sha256sum "$1" | cut -d' ' -f1
	elif have shasum; then shasum -a 256 "$1" | cut -d' ' -f1
	else die "sem sha256sum nem shasum: nao consigo conferir os checksums."
	fi
}

# expect_sha <arquivo> <sha esperado> <rotulo>
expect_sha() {
	local file="$1" want="$2" label="$3" got
	got="$(sha256_of "$file")"
	if [ "$got" != "$want" ]; then
		die "checksum de $label nao confere." \
		    "esperado: $want" \
		    "obtido:   $got" \
		    "arquivo:  $file" \
		    "" \
		    "O download pode ter sido corrompido ou interrompido." \
		    "Apague o arquivo acima e rode de novo."
	fi
	info "checksum ok: $label"
}

# --- GitHub --------------------------------------------------------------
# gh_latest_tag <owner/repo> -> tag_name da release mais recente
gh_latest_tag() {
	fetch_stdout "https://api.github.com/repos/$1/releases/latest" \
		| sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
		| head -n 1
}

# gh_asset_names <owner/repo> <tag> -> um nome de asset por linha
gh_asset_names() {
	fetch_stdout "https://api.github.com/repos/$1/releases/tags/$2" \
		| sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
}

# gh_asset_url <owner/repo> <tag> <asset>
gh_asset_url() {
	printf 'https://github.com/%s/releases/download/%s/%s\n' "$1" "$2" "$3"
}

# --- versoes -------------------------------------------------------------
# version_lt <a> <b> -> 0 se a < b  (compara so major.minor numericos)
version_lt() {
	local a="$1" b="$2"
	[ "$a" = "$b" ] && return 1
	[ "$(printf '%s\n%s\n' "$a" "$b" | sort -V | head -n 1)" = "$a" ]
}
