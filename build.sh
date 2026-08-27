#!/usr/bin/env bash
#
# build.sh - compila do zero o EBOOT.PBP (engine) e o progs.dat (QuakeC).
#
# Baixa o toolchain PSP se preciso, clona os dois forks nos commits fixados
# em sources.env e deixa o resultado em dist/.
#
# Se voce so quer JOGAR, nao use este script: use ./package.sh
#
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$ROOT/lib.sh"
# shellcheck source=sources.env
. "$ROOT/sources.env"

WORK="$ROOT/.work"
DIST="$ROOT/dist"
TOOLCHAIN="$ROOT/toolchain"
VENV="$TOOLCHAIN/qcvenv"

JOBS="$( (nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2) )"
ONLY=""
CLEAN=0

usage() {
	cat <<'EOF'
Uso: ./build.sh [opcoes]

Compila o EBOOT.PBP e o progs.dat a partir dos forks fixados em sources.env
e grava tudo em dist/, junto com dist/SHA256SUMS.txt.

Opcoes:
  --only engine        compila so o engine (EBOOT.PBP)
  --only quakec        compila so o QuakeC (progs.dat)
  --clean              apaga .work/ e dist/ antes de comecar
  -j N                 paralelismo do make (padrao: numero de nucleos)
  -h, --help           esta ajuda

Variaveis de ambiente:
  PSPDEV=<caminho>     usa um toolchain PSP que voce ja tem, em vez de baixar
  GITHUB_TOKEN=<tok>   opcional; evita o rate limit da API do GitHub

Depois de compilar, monte a pasta de jogo com:
  ./package.sh --local
EOF
}

while [ $# -gt 0 ]; do
	case "$1" in
		--only) ONLY="${2:?--only precisa de engine ou quakec}"; shift 2 ;;
		--clean) CLEAN=1; shift ;;
		-j) JOBS="${2:?-j precisa de um numero}"; shift 2 ;;
		-h|--help) usage; exit 0 ;;
		*) die "opcao desconhecida: $1" "Rode ./build.sh --help" ;;
	esac
done
case "$ONLY" in ''|engine|quakec) ;; *) die "--only aceita 'engine' ou 'quakec'" ;; esac

do_engine=1; do_quakec=1
if [ "$ONLY" = quakec ]; then do_engine=0; fi
if [ "$ONLY" = engine ]; then do_quakec=0; fi

for t in git make; do
	have "$t" || die "$t nao encontrado." "Instale com: sudo apt install $t"
done
pick_downloader

if [ "$CLEAN" -eq 1 ]; then
	step "--clean: apagando .work/ e dist/"
	rm -rf "$WORK" "$DIST"
fi
mkdir -p "$WORK" "$DIST" "$TOOLCHAIN"

# ===========================================================================
# 1. Toolchain PSP
# ===========================================================================
setup_toolchain() {
	step "[1/4] Toolchain PSP"

	if [ -n "${PSPDEV:-}" ] && [ -x "$PSPDEV/bin/psp-gcc" ]; then
		info "usando PSPDEV do ambiente: $PSPDEV"
		return 0
	fi
	if [ -n "${PSPDEV:-}" ]; then
		die "PSPDEV=$PSPDEV foi definido mas nao achei $PSPDEV/bin/psp-gcc." \
		    "Corrija o caminho ou rode sem PSPDEV para o script baixar o toolchain."
	fi
	if [ -x "$TOOLCHAIN/pspdev/bin/psp-gcc" ]; then
		PSPDEV="$TOOLCHAIN/pspdev"
		info "usando o toolchain ja baixado em toolchain/pspdev"
		return 0
	fi

	local os arch tag glibc
	os="$(uname -s)"; arch="$(uname -m)"

	# Escolha da release: releases do pspdev mais novas que ~v20250801 sao
	# compiladas em Debian 13 e abortam com "GLIBC_2.38 not found" em quem
	# tem glibc mais antiga (Debian 12 = 2.36). Nesse caso, fallback fixo.
	tag=""
	if [ "$os" = Linux ] && have ldd; then
		glibc="$(ldd --version 2>/dev/null | head -n 1 | awk '{print $NF}')"
		case "$glibc" in
			[0-9]*.[0-9]*)
				if version_lt "$glibc" "$PSPDEV_GLIBC_MIN"; then
					warn "glibc $glibc < $PSPDEV_GLIBC_MIN neste sistema."
					info "as releases novas do pspdev sao compiladas em Debian 13 e"
					info "quebrariam com \"GLIBC_2.38 not found\"; usando o fallback."
					tag="$PSPDEV_FALLBACK_TAG"
				else
					info "glibc $glibc: pode usar a release mais recente"
				fi ;;
			*) warn "nao consegui detectar a glibc; usando o fallback $PSPDEV_FALLBACK_TAG"
			   tag="$PSPDEV_FALLBACK_TAG" ;;
		esac
	fi
	if [ -z "$tag" ]; then
		tag="$(gh_latest_tag "$PSPDEV_REPO" || true)"
		[ -n "$tag" ] || tag="$PSPDEV_FALLBACK_TAG"
	fi
	info "release do pspdev: $tag"

	# Candidatos por plataforma, em ordem de preferencia.
	local -a cand=()
	case "$os/$arch" in
		Linux/x86_64)          cand=(pspdev-debian-latest.tar.gz pspdev-ubuntu-latest-x86_64.tar.gz) ;;
		Linux/aarch64|Linux/arm64) cand=(pspdev-ubuntu-24.04-arm-arm64.tar.gz) ;;
		Darwin/arm64)          cand=(pspdev-macos-latest-arm64.tar.gz) ;;
		Darwin/x86_64)         cand=(pspdev-macos-15-intel-x86_64.tar.gz pspdev-macos-13-x86_64.tar.gz) ;;
		*) die "sem toolchain pre-compilado do pspdev para $os/$arch." \
		       "Instale o pspdev na mao e rode: PSPDEV=<caminho> ./build.sh" ;;
	esac

	local names asset=""
	names="$(gh_asset_names "$PSPDEV_REPO" "$tag" || true)"
	for c in "${cand[@]}"; do
		if printf '%s\n' "$names" | grep -qxF "$c"; then asset="$c"; break; fi
	done
	if [ -z "$asset" ]; then
		asset="${cand[0]}"
		warn "nao listei os assets de $tag; tentando $asset direto"
	fi

	local tgz="$TOOLCHAIN/$asset"
	if [ ! -f "$tgz" ]; then
		info "baixando $asset (~150 MB)..."
		fetch_file "$(gh_asset_url "$PSPDEV_REPO" "$tag" "$asset")" "$tgz"
	else
		info "em cache: $asset"
	fi

	info "extraindo em toolchain/pspdev..."
	rm -rf "$TOOLCHAIN/pspdev" "$TOOLCHAIN/.untar"
	mkdir -p "$TOOLCHAIN/.untar"
	tar -xzf "$tgz" -C "$TOOLCHAIN/.untar"
	# o tarball traz uma pasta pspdev/ na raiz
	if [ -d "$TOOLCHAIN/.untar/pspdev" ]; then
		mv "$TOOLCHAIN/.untar/pspdev" "$TOOLCHAIN/pspdev"
	else
		local inner
		inner="$(find "$TOOLCHAIN/.untar" -maxdepth 2 -type d -name bin -print -quit)"
		[ -n "$inner" ] || die "layout inesperado dentro de $asset"
		mv "$(dirname "$inner")" "$TOOLCHAIN/pspdev"
	fi
	rm -rf "$TOOLCHAIN/.untar"

	PSPDEV="$TOOLCHAIN/pspdev"
	[ -x "$PSPDEV/bin/psp-gcc" ] || die "psp-gcc nao apareceu em $PSPDEV/bin apos extrair."

	if ! "$PSPDEV/bin/psp-gcc" --version >/dev/null 2>&1; then
		die "o psp-gcc baixado nao roda neste sistema." \
		    "Se a mensagem falar de GLIBC, sua glibc e antiga demais para a release $tag." \
		    "Force o fallback assim:" \
		    "  rm -rf toolchain/pspdev && PSPDEV= ./build.sh   # detecta a glibc" \
		    "ou instale o pspdev na mao e rode: PSPDEV=<caminho> ./build.sh"
	fi
	info "psp-gcc: $("$PSPDEV/bin/psp-gcc" -dumpversion)"
}

# ===========================================================================
# 2. Clonar os forks nos commits fixados
# ===========================================================================
# pin_checkout <dir> <repo> <branch> <commit>
pin_checkout() {
	local dir="$1" repo="$2" branch="$3" commit="$4"

	if [ -d "$dir/.git" ]; then
		if [ "$(git -C "$dir" rev-parse HEAD)" = "$commit" ]; then
			info "$(basename "$dir"): ja em ${commit:0:9}"
			return 0
		fi
		info "$(basename "$dir"): HEAD diferente do pin, refazendo"
		rm -rf "$dir"
	fi

	info "$(basename "$dir"): clonando $branch @ ${commit:0:9}"
	rm -rf "$dir"
	mkdir -p "$dir"
	git -C "$dir" init -q
	git -C "$dir" remote add origin "$repo"
	# Tenta buscar so o commit fixado; se o servidor nao permitir, cai para
	# o branch inteiro e faz checkout do commit.
	if git -C "$dir" fetch -q --depth 1 origin "$commit" 2>/dev/null; then
		git -C "$dir" checkout -q FETCH_HEAD
	else
		git -C "$dir" fetch -q origin "$branch"
		git -C "$dir" checkout -q "$commit" \
			|| die "o commit $commit nao existe em $repo ($branch)."
	fi
	[ "$(git -C "$dir" rev-parse HEAD)" = "$commit" ] \
		|| die "checkout de $dir nao ficou no commit fixado $commit."
}

fetch_sources() {
	step "[2/4] Clonando os forks nos commits fixados"
	if [ "$do_engine" -eq 1 ]; then
		pin_checkout "$WORK/vril-engine" "$ENGINE_REPO" "$ENGINE_BRANCH" "$ENGINE_COMMIT"
	fi
	if [ "$do_quakec" -eq 1 ]; then
		pin_checkout "$WORK/quakec" "$QUAKEC_REPO" "$QUAKEC_BRANCH" "$QUAKEC_COMMIT"
	fi
}

# ===========================================================================
# 3. Engine -> EBOOT.PBP
# ===========================================================================
build_engine() {
	step "[3/4] Compilando o engine (EBOOT.PBP)"
	export PSPDEV
	export PSPSDK="$PSPDEV/psp/sdk"
	export PATH="$PSPDEV/bin:$PSPDEV/psp/bin:$PATH"
	info "make -f Makefile.psp WERROR=1 -j$JOBS"
	make -C "$WORK/vril-engine" -f Makefile.psp WERROR=1 -j"$JOBS"
	local out="$WORK/vril-engine/build/psp/bin/EBOOT.PBP"
	[ -f "$out" ] || die "o make terminou mas nao achei $out"
	cp -f "$out" "$DIST/EBOOT.PBP"
	info "dist/EBOOT.PBP ($(du -h "$DIST/EBOOT.PBP" | cut -f1))"
}

# ===========================================================================
# 4. QuakeC -> progs.dat
# ===========================================================================
setup_venv() {
	have python3 || die "python3 nao encontrado (necessario so para o QuakeC)." \
		"Instale com: sudo apt install python3 python3-venv"
	if [ ! -x "$VENV/bin/python" ]; then
		info "criando o venv em toolchain/qcvenv"
		python3 -m venv "$VENV" || die \
			"falha ao criar o venv." \
			"No Debian/Ubuntu instale: sudo apt install python3-venv"
	fi
	local pyver
	pyver="$("$VENV/bin/python" -c 'import sys;print("%d.%d"%sys.version_info[:2])')"
	info "python do venv: $pyver"
	if ! "$VENV/bin/python" -c 'import pandas,fastcrc,colorama' >/dev/null 2>&1; then
		info "instalando as dependencias de requirements-qc.txt"
		"$VENV/bin/python" -m pip install -q --upgrade pip >/dev/null
		"$VENV/bin/python" -m pip install -q -r "$ROOT/requirements-qc.txt" || die \
			"falha ao instalar as dependencias do QuakeC." \
			"O pin pandas==1.5.3 e obrigatorio (o pandas 2.x quebra o" \
			"bin/qc_hash_generator.py), e ele so tem wheel pronta ate o" \
			"Python 3.11. Se o seu python3 e 3.12+, aponte um 3.11:" \
			"  rm -rf toolchain/qcvenv" \
			"  python3.11 -m venv toolchain/qcvenv && ./build.sh --only quakec"
	fi
	info "pandas $("$VENV/bin/python" -c 'import pandas;print(pandas.__version__)') (pin obrigatorio: 1.5.3)"
}

build_quakec() {
	step "[4/4] Compilando o QuakeC (progs.dat)"
	setup_venv
	local qc="$WORK/quakec"
	chmod +x "$qc/tools/qc-compiler-gnu.sh" "$qc"/bin/fteqcc-cli-* 2>/dev/null || true
	info "tools/qc-compiler-gnu.sh"
	(
		cd "$qc"
		# shellcheck disable=SC1091
		. "$VENV/bin/activate"
		tools/qc-compiler-gnu.sh
	)
	local out="$qc/build/standard/progs.dat"
	[ -f "$out" ] || die "o compilador terminou mas nao achei $out"
	cp -f "$out" "$DIST/progs.dat"
	info "dist/progs.dat ($(du -h "$DIST/progs.dat" | cut -f1))"
}

# ===========================================================================
main() {
	if [ "$do_engine" -eq 1 ]; then setup_toolchain
	else step "[1/4] Toolchain PSP"; info "nao precisa (--only quakec)"; fi

	fetch_sources

	if [ "$do_engine" -eq 1 ]; then build_engine
	else step "[3/4] Engine (pulado)"; fi

	if [ "$do_quakec" -eq 1 ]; then build_quakec
	else step "[4/4] QuakeC (pulado)"; fi

	step "Gravando dist/SHA256SUMS.txt"
	(
		cd "$DIST"
		: > SHA256SUMS.txt
		for f in EBOOT.PBP progs.dat; do
			[ -f "$f" ] || continue
			if have sha256sum; then sha256sum "$f" >> SHA256SUMS.txt
			else shasum -a 256 "$f" >> SHA256SUMS.txt; fi
		done
		cat SHA256SUMS.txt
	)

	cat <<EOF

${C_G}Compilacao concluida.${C_0} Artefatos em ${C_B}dist/${C_0}:
$(cd "$DIST" && ls -1)

Fontes usadas (fixadas):
  engine  $ENGINE_BRANCH @ ${ENGINE_COMMIT:0:9}
  quakec  $QUAKEC_BRANCH @ ${QUAKEC_COMMIT:0:9}

${C_B}Proximo passo:${C_0} montar a pasta de jogo com os assets do nzp-team:

    ${C_B}./package.sh --local${C_0}

Isso baixa a nightly oficial, troca o EBOOT.PBP e o nzp/progs.dat pelos que
acabaram de sair de dist/, e deixa a pasta nzportable/ pronta para copiar.
EOF
}

main
