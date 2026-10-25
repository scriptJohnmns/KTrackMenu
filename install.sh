#!/usr/bin/env bash
# =============================================================================
# install.sh — instala (ou remove) o KTrackMenu em qualquer distro com KDE Plasma 6
#
# O que ele faz:
#   1. descobre o gerenciador de pacotes (dnf, pacman, zypper ou apt) e instala
#      o que é preciso para compilar;
#   2. compila o programa na pasta build/;
#   3. instala em ~/.local (ou em /usr/local, com --system);
#   4. se o KTrackMenu já estava rodando, reinicia para usar a versão nova.
#
# Uso:
#   ./install.sh               instala para o seu usuário (~/.local)
#   ./install.sh --system      instala para todos os usuários (/usr/local, pede senha)
#   ./install.sh --no-deps     pula a instalação de dependências
#   ./install.sh --uninstall   remove o programa (o seu menu.json é mantido)
#   ./install.sh --help        mostra esta ajuda
#
# Para atualizar: "git pull" e rode ./install.sh de novo.
# =============================================================================

# -e: para no primeiro erro. -u: erro se usar variável que não existe.
# -o pipefail: um erro no meio de um "a | b" também conta como erro.
set -euo pipefail

# Pasta onde este script está (a raiz do projeto), não importa de onde ele foi chamado.
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SOURCE_DIR/build"

PREFIX="$HOME/.local"
SUDO=""          # comando para instalar em pasta do sistema ("" = não precisa)
INSTALL_DEPS=1
ACTION="install"

# ---- Mensagens coloridas (só se a saída for um terminal) ----
if [[ -t 1 ]]; then
    BOLD=$'\e[1m'; GREEN=$'\e[32m'; YELLOW=$'\e[33m'; RED=$'\e[31m'; RESET=$'\e[0m'
else
    BOLD=""; GREEN=""; YELLOW=""; RED=""; RESET=""
fi
step() { echo "${BOLD}==> $*${RESET}"; }
ok()   { echo "${GREEN}✓ $*${RESET}"; }
warn() { echo "${YELLOW}! $*${RESET}"; }
die()  { echo "${RED}✗ $*${RESET}" >&2; exit 1; }

usage() {
    # Imprime o bloco de comentário do começo do arquivo (linhas 3 a 19).
    sed -n '3,19p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# ---- Lê as opções da linha de comando ----
for arg in "$@"; do
    case "$arg" in
        --system)    PREFIX="/usr/local"; SUDO="sudo" ;;
        --no-deps)   INSTALL_DEPS=0 ;;
        --uninstall) ACTION="uninstall" ;;
        -h|--help)   usage; exit 0 ;;
        *)           die "Opção desconhecida: $arg (use --help)" ;;
    esac
done

# Rodar o script inteiro como root bagunçaria as permissões de ~/.local e da build/.
[[ $EUID -eq 0 ]] && die "Não rode como root. O script pede a senha (sudo) só quando precisa."

# Encerra o KTrackMenu se ele estiver rodando. Devolve 0 se estava rodando.
stop_running() {
    if pgrep -x ktrackmenu >/dev/null; then
        # Primeiro pede com educação; se não sair em 2 s, força.
        "$PREFIX/bin/ktrackmenu" --quit >/dev/null 2>&1 || pkill -x ktrackmenu || true
        for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x ktrackmenu >/dev/null || return 0; sleep 0.2; done
        pkill -x ktrackmenu || true
        return 0
    fi
    return 1
}

# O app se chamava TrackpMenu. Fecha e remove a versão antiga (executável e
# atalho no menu de apps). Devolve 0 se ela estava rodando. A configuração e o
# atalho de teclado são migrados pelo próprio KTrackMenu na primeira vez que abre.
remove_legacy() {
    local was=1
    if pgrep -x trackpmenu >/dev/null; then
        was=0
        pkill -x trackpmenu || true
        for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x trackpmenu >/dev/null || break; sleep 0.2; done
    fi
    for p in "$HOME/.local" "/usr/local"; do
        for f in "$p/bin/trackpmenu" "$p/share/applications/io.github.trackpmenu.desktop"; do
            [[ -e $f ]] || continue
            if [[ $p == /usr/local ]]; then sudo rm -fv "$f"; else rm -fv "$f"; fi
        done
    done
    return $was
}

# =============================================================================
# Desinstalar
# =============================================================================
if [[ $ACTION == "uninstall" ]]; then
    step "Removendo o KTrackMenu"
    stop_running || true
    remove_legacy || true
    # O CMake anota em install_manifest.txt cada arquivo que instalou.
    if [[ -f "$BUILD_DIR/install_manifest.txt" ]]; then
        while IFS= read -r file; do
            [[ -n $file ]] && $SUDO rm -fv "$file"
        done < "$BUILD_DIR/install_manifest.txt"
    else
        # Sem o manifesto (ex.: a pasta build/ foi apagada), remove os caminhos conhecidos.
        for p in "$HOME/.local" "/usr/local"; do
            [[ $p == /usr/local ]] && s="sudo" || s=""
            [[ -e "$p/bin/ktrackmenu" ]] && $s rm -fv "$p/bin/ktrackmenu"
            [[ -e "$p/share/applications/io.github.ktrackmenu.desktop" ]] && $s rm -fv "$p/share/applications/io.github.ktrackmenu.desktop"
        done
    fi
    # Arquivos que o próprio programa cria: script do KWin e "Iniciar com a sessão".
    rm -rfv "$HOME/.local/share/ktrackmenu"
    rm -fv "$HOME/.config/autostart/io.github.ktrackmenu.desktop"
    ok "Removido. O seu menu continua em ~/.config/ktrackmenu/ (apague a pasta se quiser)."
    exit 0
fi

# =============================================================================
# Instalar
# =============================================================================

# ---- Confere se é KDE Plasma 6 (só avisa: dá para compilar mesmo assim) ----
if command -v plasmashell >/dev/null; then
    plasma_version="$(plasmashell --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -n1 || true)"
    if [[ ${plasma_version%%.*} != "6" ]]; then
        warn "Plasma $plasma_version encontrado. O KTrackMenu precisa do Plasma 6."
    fi
else
    warn "plasmashell não encontrado. O KTrackMenu foi feito para o KDE Plasma 6 e não funciona em outros ambientes."
fi

# ---- Dependências ----
# Cada distro dá um nome diferente para o mesmo pacote. As listas abaixo têm o
# necessário para compilar e os módulos QML usados pelas telas (Kirigami,
# seletor de ícones e campo de atalho).
install_deps() {
    if command -v pacman >/dev/null; then
        step "Instalando dependências (Arch / CachyOS / Manjaro…)"
        sudo pacman -S --needed base-devel cmake extra-cmake-modules \
            qt6-base qt6-declarative qt6-wayland layer-shell-qt \
            kconfig kglobalaccel kdbusaddons kservice kio kwindowsystem \
            kirigami kiconthemes kdeclarative
    elif command -v dnf >/dev/null; then
        step "Instalando dependências (Fedora)"
        sudo dnf install cmake gcc-c++ extra-cmake-modules \
            qt6-qtbase-devel qt6-qtdeclarative-devel qt6-qtwayland-devel layer-shell-qt-devel \
            kf6-kconfig-devel kf6-kglobalaccel-devel kf6-kdbusaddons-devel kf6-kservice-devel \
            kf6-kio-devel kf6-kwindowsystem-devel \
            kf6-kirigami kf6-kiconthemes kf6-kdeclarative
    elif command -v zypper >/dev/null; then
        step "Instalando dependências (openSUSE)"
        sudo zypper install cmake gcc-c++ kf6-extra-cmake-modules \
            qt6-base-devel qt6-declarative-devel qt6-wayland-devel layer-shell-qt6-devel \
            kf6-kconfig-devel kf6-kglobalaccel-devel kf6-kdbusaddons-devel kf6-kservice-devel \
            kf6-kio-devel kf6-kwindowsystem-devel \
            kf6-kirigami kf6-kiconthemes kf6-kdeclarative
    elif command -v apt-get >/dev/null; then
        step "Instalando dependências (Debian / Ubuntu / KDE neon…)"
        sudo apt-get install cmake g++ extra-cmake-modules \
            qt6-base-dev qt6-declarative-dev qt6-wayland-dev liblayershellqtinterface-dev \
            libkf6config-dev libkf6globalaccel-dev libkf6dbusaddons-dev libkf6service-dev \
            libkf6kio-dev libkf6windowsystem-dev \
            qml6-module-org-kde-kirigami qml6-module-org-kde-iconthemes qml6-module-org-kde-kquickcontrols \
            qml6-module-qtquick qml6-module-qtquick-controls qml6-module-qtquick-layouts qml6-module-qtquick-dialogs \
            qml6-module-qtquick-window qml6-module-qtquick-effects qml6-module-qtqml-workerscript
    else
        warn "Gerenciador de pacotes não reconhecido. Instale as dependências do README e rode com --no-deps."
        return 1
    fi
}

if [[ $INSTALL_DEPS -eq 1 ]]; then
    install_deps || die "Não foi possível instalar as dependências. Veja o README (seção Dependências) e tente com --no-deps."
fi

command -v cmake >/dev/null || die "cmake não encontrado. Instale as dependências primeiro."

# ---- Compilar ----
step "Compilando (pasta build/)"
# Uma build/ feita quando o projeto ainda se chamava TrackpMenu é descartada.
if grep -q "CMAKE_PROJECT_NAME:STATIC=trackpmenu" "$BUILD_DIR/CMakeCache.txt" 2>/dev/null; then
    rm -rf "$BUILD_DIR"
fi
# Se a build/ antiga foi configurada para outro prefixo, o CMake reaproveita o
# valor salvo no cache; passar o -D de novo sempre sobrescreve.
cmake -S "$SOURCE_DIR" -B "$BUILD_DIR" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -Wno-dev >/dev/null
cmake --build "$BUILD_DIR" -j"$(nproc)"

# ---- Instalar ----
step "Instalando em $PREFIX"
was_running=0
stop_running && was_running=1
if remove_legacy; then
    was_running=1
    ok "Versão antiga (TrackpMenu) removida. Configuração e atalho são migrados ao abrir."
fi
$SUDO cmake --install "$BUILD_DIR"
ok "KTrackMenu instalado: $PREFIX/bin/ktrackmenu"

# O app usa um script dentro do KWin; ele é recriado ao iniciar, então apagar
# a cópia antiga garante que a versão nova seja carregada.
rm -f "$HOME/.local/share/ktrackmenu/"*.js 2>/dev/null || true

if [[ $was_running -eq 1 ]]; then
    # setsid + redirecionamentos: o programa continua rodando depois que o script termina.
    setsid -f "$PREFIX/bin/ktrackmenu" --daemon >/dev/null 2>&1 </dev/null
    ok "KTrackMenu reiniciado com a versão nova."
fi

# ~/.local/bin fora do PATH só atrapalha quem quer usar o comando no terminal
# (o atalho no menu de apps usa o caminho completo).
if [[ ":$PATH:" != *":$PREFIX/bin:"* ]]; then
    warn "$PREFIX/bin não está no PATH. No terminal, use o caminho completo ou adicione a pasta ao PATH."
fi

cat <<EOF

${BOLD}Próximos passos:${RESET}
  1. Abra "KTrackMenu" no menu de aplicativos (ou rode: $PREFIX/bin/ktrackmenu).
  2. Na aba Comportamento, escolha o atalho (ex.: Meta+Z) e marque "Iniciar com a sessão".
  3. Já tem um menu de outro computador? Copie o menu.json para ~/.config/ktrackmenu/.
EOF
