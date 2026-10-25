# =============================================================================
# CMakeLists.txt — "receita" de compilação do KTrackMenu
#
# O CMake lê este arquivo e gera os Makefiles que de fato compilam o programa.
# Uso típico (ver README.md):
#   cmake -B build -DCMAKE_INSTALL_PREFIX=$HOME/.local   # configura
#   cmake --build build                                  # compila
#   cmake --install build                                # instala em ~/.local
# =============================================================================

# Versão mínima do CMake necessária para entender os comandos abaixo.
cmake_minimum_required(VERSION 3.22)

# Nome e versão do projeto. A versão vira a variável ${PROJECT_VERSION},
# que é repassada ao código C++ mais abaixo (aparece na aba "Sobre").
project(ktrackmenu VERSION 0.1.0 LANGUAGES CXX)

# Usa C++20 e falha se o compilador não suportar.
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ECM (Extra CMake Modules) é um pacote do KDE com funções prontas para o CMake.
# KDEInstallDirs define as pastas padrão de instalação (bin, share/applications…).
find_package(ECM 6.0 REQUIRED NO_MODULE)
list(APPEND CMAKE_MODULE_PATH ${ECM_MODULE_PATH})
include(KDEInstallDirs)

# Bibliotecas de que o programa depende ("REQUIRED" = para tudo se não encontrar).
#   Qt6          — framework de interface (núcleo, gráficos, QML, D-Bus, Widgets)
#   KF6          — KDE Frameworks: arquivos de configuração do KDE, atalhos
#                  globais, instância única via D-Bus, lista de aplicativos
#                  instalados, abertura de apps/URLs e desfoque do fundo
#   LayerShellQt — permite criar a janela "por cima de tudo" no Wayland
find_package(Qt6 6.6 REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2 DBus Widgets)
find_package(KF6 6.0 REQUIRED COMPONENTS Config GlobalAccel DBusAddons Service KIO WindowSystem)
find_package(LayerShellQt 6.0 REQUIRED)

# Configurações recomendadas pelo Qt 6 (por exemplo, roda o "moc" automaticamente,
# a ferramenta que gera o código por trás de sinais, slots e propriedades).
qt_standard_project_setup(REQUIRES 6.6)
# Comportamento novo do Qt para módulos QML (como o arquivo qmldir é gerado).
qt_policy(SET QTP0004 NEW)

# O executável e os arquivos C++ que o compõem.
qt_add_executable(ktrackmenu
    src/main.cpp
    src/windowtracker.cpp
    src/windowtracker.h
    src/configstore.cpp
    src/configstore.h
    src/menucontroller.cpp
    src/menucontroller.h
    src/systembridge.cpp
    src/systembridge.h
    src/togglestates.cpp
    src/togglestates.h
    src/mediaplayers.cpp
    src/mediaplayers.h
)

# As telas em QML ficam embutidas dentro do executável, num "módulo" chamado
# KTrackMenu. Depois o C++ cria as janelas pelo nome (ex.: "Overlay", "Settings").
qt_add_qml_module(ktrackmenu
    URI KTrackMenu
    VERSION 1.0
    QML_FILES
        qml/Overlay.qml
        qml/Settings.qml
        qml/ItemEditor.qml
        qml/RingPreview.qml
)

# Cria a macro KTRACKMENU_VERSION no C++ com o valor da versão do projeto.
target_compile_definitions(ktrackmenu PRIVATE KTRACKMENU_VERSION="${PROJECT_VERSION}")

# Liga ("linka") o executável às bibliotecas encontradas acima.
target_link_libraries(ktrackmenu PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Widgets             # ícone da bandeja e seletor de ícones do KDE
    Qt6::DBus
    KF6::ConfigCore          # ler/gravar plasmanotifyrc e kwinrc (itens liga/desliga)
    KF6::GlobalAccel
    KF6::DBusAddons
    KF6::Service
    KF6::KIOGui
    KF6::WindowSystem        # desfoque (blur) atrás do menu
    LayerShellQt::Interface
)

# O que o "cmake --install" copia: o executável para bin/ e o arquivo .desktop
# para share/applications/ (é ele que faz o app aparecer no menu do KDE).
install(TARGETS ktrackmenu ${KDE_INSTALL_TARGETS_DEFAULT_ARGS})
# O .desktop é gerado com o caminho completo do executável no Exec=, para o
# atalho do menu de apps funcionar mesmo se ~/.local/bin não estiver no PATH.
configure_file(data/io.github.ktrackmenu.desktop.in ${CMAKE_CURRENT_BINARY_DIR}/io.github.ktrackmenu.desktop @ONLY)
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/io.github.ktrackmenu.desktop DESTINATION ${KDE_INSTALL_APPDIR})
