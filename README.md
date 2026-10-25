# TrackpMenu

Menu radial de atalhos para KDE Plasma 6 (Wayland), aberto com **dois toques no TrackPoint**
de ThinkPads recentes (T14 Gen 5, X1 Carbon Gen 12…).

```
toque duplo → thinkpad_acpi emite KEY_PROG4 → atalho global (KGlobalAccel)
            → overlay layer-shell com o menu em volta do cursor → ação
```

## Uso

- **Abrir:** dois toques no TrackPoint (ou o atalho escolhido nas configurações).
- **Escolher:** empurre o TrackPoint na direção do item e clique com o botão esquerdo.
  Também funciona passar o cursor por cima do item, usar a roda, as setas ou as teclas `1`–`9`.
- **Submenus:** o botão direito abre o submenu apontado (dá para fazer sem soltar o atalho).
- **Voltar/fechar:** clique no centro, `Backspace` (volta) ou `Esc` (fecha).

Tipos de item: aplicativo, comando de shell, atalho global do KDE (via D-Bus), URL/arquivo e submenu.

## Dependências (Fedora)

```sh
sudo dnf install cmake gcc-c++ extra-cmake-modules \
  qt6-qtbase-devel qt6-qtdeclarative-devel qt6-qtwayland-devel \
  layer-shell-qt-devel kf6-kglobalaccel-devel kf6-kdbusaddons-devel \
  kf6-kservice-devel kf6-kio-devel
```

Em tempo de execução são usados também `kf6-kirigami`, `kf6-kdeclarative` e `kf6-kiconthemes`
(já presentes no Plasma).

## Compilar e instalar

```sh
cmake -B build -DCMAKE_INSTALL_PREFIX=$HOME/.local
cmake --build build
cmake --install build
```

- `trackpmenu` abre as configurações (e deixa o serviço rodando em segundo plano).
- `trackpmenu --daemon` só inicia o serviço (é o que o "Iniciar com a sessão" usa).
- `trackpmenu --toggle` mostra ou esconde o menu.
- `trackpmenu --quit` encerra o serviço.

## Configuração

Fica em `~/.config/trackpmenu/menu.json`. Pode ser editada pela interface ou à mão:
o programa recarrega o arquivo quando ele muda (útil para scripts ou um servidor MCP).

```json
{
  "version": 1,
  "appearance": { "radius": 120, "itemSize": 64 },
  "items": [
    { "label": "Terminal", "icon": "utilities-terminal", "type": "app", "app": "org.kde.konsole.desktop" },
    { "label": "Comando", "icon": "run-build", "type": "command", "command": "playerctl play-pause" },
    { "label": "Visão geral", "icon": "view-app-grid", "type": "shortcut", "component": "/component/kwin", "shortcut": "Overview" },
    { "label": "Site", "icon": "internet-web-browser", "type": "url", "url": "https://kde.org" },
    { "label": "Mais", "icon": "folder", "type": "menu", "items": [] }
  ]
}
```

## Verificando o toque duplo

```sh
cat /sys/devices/platform/thinkpad_acpi/doubletap_enable   # 1 = ligado
sudo evtest   # escolha "ThinkPad Extra Buttons" e toque duas vezes: deve aparecer KEY_PROG4
```
