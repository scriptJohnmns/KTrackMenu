# KTrackMenu

Menu radial de atalhos para o **KDE Plasma 6**, pensado para o TrackPoint dos ThinkPads
(mas funciona com qualquer mouse ou touchpad).

Aperte o atalho, empurre o cursor na direção de um item e clique (ou solte o atalho). O menu abre
em volta do cursor, então a mão não precisa sair do teclado e a memória muscular faz o resto.

```
            Terminal
     Bloquear        Arquivos
 Calculadora   (•)   Navegador        ← empurre o cursor na direção do item
     Ligar/desligar  Visão geral
            Mídia   Captura
```

## Recursos

- **Anel de atalhos** que abre onde está o cursor, com até 9 itens acessíveis também pelas teclas `1`–`9`.
- **Segurar e soltar:** segure o atalho (ex.: `Meta+Z`), aponte e solte para executar, sem nenhum clique.
- **Submenus**, com quantos níveis você quiser.
- **Menus por aplicativo:** com um app em foco (Konsole, Firefox…), os itens dele aparecem num anel
  interno, e o menu geral continua igual no anel de fora.
- **Liga/desliga** com o estado na tela: Wi-Fi, Bluetooth, Não perturbe e Luz noturna.
- **Controle de mídia (MPRIS):** Tocar/Pausar, Próxima e Anterior no player que está tocando
  (Spotify, navegador, VLC…), com capa, música e artista no centro do anel.
- **Janelas abertas:** um submenu montado na hora para pular para qualquer janela.
- **Manter aberto:** itens como Play/Pause e Mudo não fecham o menu, para você apertar vários em sequência.
- **Aparência configurável:** tamanho, formato dos itens, cor de destaque, opacidade, desfoque e animações.
- Tudo fica num único arquivo, `~/.config/ktrackmenu/menu.json`, fácil de copiar para outro computador.

## Requisitos

- **KDE Plasma 6**, de preferência no Wayland. Existe um modo X11, mas ele não foi testado.
- Linux com Qt 6.6 ou mais novo e KDE Frameworks 6.

O KTrackMenu depende de partes do KDE (atalhos globais, scripts do KWin, layer-shell), então
**não funciona no GNOME, em outros ambientes, nem no Windows ou macOS**.

## Instalação

```sh
git clone https://github.com/scriptJohnmns/ktrackmenu.git
cd ktrackmenu
./install.sh
```

O `install.sh` descobre a sua distro, instala o que é preciso para compilar (pede a senha do
`sudo` só nessa hora), compila e instala em `~/.local`. Se o KTrackMenu já estiver rodando, ele é
reiniciado com a versão nova.

| Comando                    | O que faz                                                  |
|----------------------------|------------------------------------------------------------|
| `./install.sh`             | instala para o seu usuário (`~/.local`)                    |
| `./install.sh --system`    | instala para todos os usuários (`/usr/local`, pede senha)  |
| `./install.sh --no-deps`   | pula a instalação de dependências                          |
| `./install.sh --uninstall` | remove o programa (o seu `menu.json` é mantido)            |
| `./install.sh --help`      | mostra a ajuda                                             |

Distros reconhecidas: **Fedora** (dnf), **Arch, CachyOS, Manjaro, EndeavourOS** (pacman),
**openSUSE** (zypper) e **Debian, Ubuntu, Kubuntu, KDE neon** (apt). Até agora só o Fedora foi
testado. Se faltar algum pacote na sua distro, abra uma issue.

### Vindo do TrackpMenu?

O projeto se chamava **TrackpMenu**. Rodar o `./install.sh` remove a versão antiga, e na primeira
vez que o KTrackMenu abre ele copia sozinho o seu menu (`~/.config/trackpmenu` →
`~/.config/ktrackmenu`), o atalho de teclado e o "Iniciar com a sessão". A pasta antiga fica
intacta, como cópia de segurança.

### Atualizar

```sh
cd ktrackmenu
git pull
./install.sh --no-deps
```

### Primeiro uso

1. Abra **KTrackMenu** no menu de aplicativos. A janela de configurações aparece e o programa fica
   rodando em segundo plano, com um ícone na bandeja.
2. Na aba **Comportamento**:
   - escolha o **atalho**. O padrão é a tecla ★ (`Fn+F12` nos ThinkPads), mas um atalho com
     modificador, como `Meta+Z`, permite usar o "segurar e soltar";
   - marque **Iniciar com a sessão**, para o KTrackMenu abrir sozinho ao entrar no KDE.
3. Aperte o atalho e teste.

### Compilar à mão

Se preferir não usar o script, instale as dependências da sua distro (as listas estão dentro do
`install.sh`) e rode:

```sh
cmake -B build -DCMAKE_INSTALL_PREFIX=$HOME/.local
cmake --build build
cmake --install build
```

## Como usar

| Ação                        | Como fazer                                                                    |
|-----------------------------|-------------------------------------------------------------------------------|
| Abrir o menu                | o atalho escolhido (ou `ktrackmenu --toggle`)                                 |
| Apontar um item             | mova o cursor na direção dele, ou gire a roda do mouse, ou use as setas/Tab  |
| Executar                    | clique esquerdo, `Enter`/`Espaço`, ou a tecla `1`–`9` do item                 |
| Segurar e soltar            | segure o atalho, aponte e **solte**: o item apontado é executado              |
| Entrar num submenu          | clique esquerdo ou **direito** (o direito funciona sem soltar o atalho)       |
| Voltar um nível             | clique no centro do anel, ou `Backspace`                                      |
| Fechar                      | clique **fora** do anel, `Esc`, ou o atalho de novo                           |

Dicas:

- **Empurrão curto e longo:** com um menu de aplicativo ativo, um empurrão curto escolhe um item
  do anel interno (o do app) e um empurrão mais longo escolhe um do anel de fora (o geral).
- **Segurar e soltar** só funciona com atalhos que usam `Meta`, `Ctrl`, `Alt` ou `Shift`. Um toque
  rápido no atalho (menos de 250 ms) só abre o menu, que fica esperando o clique.
- O menu tem uma **zona morta** no centro: o cursor precisa sair um pouco do meio antes de
  selecionar algo, então abrir o menu nunca escolhe um item sem querer.

## Tipos de item

Cada item tem um nome (`label`), um ícone (`icon`, qualquer nome de ícone do tema do KDE) e um
tipo (`type`). Tudo pode ser criado pela janela de configurações. Os exemplos abaixo mostram
como cada tipo fica no `menu.json`.

| Tipo       | O que faz                                          | Campos              |
|------------|----------------------------------------------------|---------------------|
| `app`      | abre um aplicativo                                 | `app`               |
| `command`  | roda um comando de shell                           | `command`           |
| `shortcut` | aciona um atalho global do KDE                     | `component`, `shortcut` |
| `url`      | abre um site, arquivo ou pasta no programa padrão  | `url`               |
| `toggle`   | liga/desliga Wi-Fi, Bluetooth etc.                 | `toggle`            |
| `media`    | controla o player que está tocando                 | `action`            |
| `windows`  | submenu com as janelas abertas                     | (nenhum)            |
| `menu`     | submenu                                            | `items`             |

### Abrir um aplicativo

O `app` é o nome do arquivo `.desktop` do programa. Na janela de configurações é só escolher
na lista.

```json
{ "label": "Terminal", "icon": "utilities-terminal", "type": "app", "app": "org.kde.konsole.desktop" }
```

### Rodar um comando

O comando roda com `/bin/sh -c`, a partir da pasta pessoal. O editor traz alguns prontos
(volume, captura de tela, bloquear, suspender…).

```json
{ "label": "Volume +5%", "icon": "audio-volume-high", "type": "command",
  "command": "wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+", "keepOpen": true }
```

### Acionar um atalho do KDE

Funciona como se a tecla de atalho tivesse sido apertada. O editor lista todos os componentes e
ações disponíveis. Alguns exemplos:

```json
{ "label": "Visão geral", "icon": "view-app-grid", "type": "shortcut", "component": "/component/kwin", "shortcut": "Overview" }
{ "label": "Bloquear", "icon": "system-lock-screen", "type": "shortcut", "component": "/component/ksmserver", "shortcut": "Lock Session" }
```

### Abrir um site, arquivo ou pasta

Aceita endereços, caminhos absolutos e caminhos começando com `~`.

```json
{ "label": "Downloads", "icon": "folder-downloads", "type": "url", "url": "~/Downloads" }
{ "label": "KDE", "icon": "internet-web-browser", "type": "url", "url": "https://kde.org" }
```

### Ligar/desligar

`toggle` pode ser `wifi`, `bluetooth`, `dnd` (Não perturbe) ou `nightlight` (Luz noturna). No
anel, uma bolinha verde no canto mostra que está ligado, e o centro mostra "Ligado"/"Desligado".

```json
{ "label": "Wi-Fi", "icon": "network-wireless", "type": "toggle", "toggle": "wifi" }
```

### Controle de mídia

`action` pode ser `playpause`, `next` ou `previous`. O comando vai para o player que está
tocando. Se nenhum estiver, vai para o último que tocou. Sempre que houver um item de mídia no
anel, o centro mostra a capa, a música e o artista, e o ícone de Play/Pause acompanha o estado.

```json
{ "label": "Mídia", "icon": "applications-multimedia", "type": "menu", "items": [
  { "label": "Tocar/Pausar", "icon": "media-playback-start", "type": "media", "action": "playpause" },
  { "label": "Próxima", "icon": "media-skip-forward", "type": "media", "action": "next" },
  { "label": "Anterior", "icon": "media-skip-backward", "type": "media", "action": "previous" },
  { "label": "Mudo", "icon": "audio-volume-muted", "type": "command",
    "command": "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle", "keepOpen": true }
] }
```

### Janelas abertas

Monta um submenu na hora com até 12 janelas, da mais recente para a mais antiga. Escolher uma
traz ela para a frente.

```json
{ "label": "Janelas", "icon": "preferences-system-windows", "type": "windows" }
```

### Submenu

```json
{ "label": "Sistema", "icon": "preferences-system", "type": "menu", "items": [
  { "label": "Suspender", "icon": "system-suspend", "type": "command", "command": "systemctl suspend" },
  { "label": "Bloquear", "icon": "system-lock-screen", "type": "command", "command": "loginctl lock-session" }
] }
```

### Manter o menu aberto

Qualquer item que executa algo aceita `"keepOpen": true`. O menu continua na tela depois de
executar, e o item dá uma "piscada" para confirmar o clique. No editor, é a opção **Depois de
executar: Manter o menu aberto**. Se o campo não existir, só os itens de mídia ficam abertos.

## Menus por aplicativo

Na aba **Itens do menu**, escolha um aplicativo no seletor do topo e adicione itens para ele.
Quando esse app estiver em foco, os itens aparecem num **anel interno**, menor, e o anel de fora
continua sendo o menu geral de sempre.

No `menu.json` eles ficam em `appMenus`. O `app` é o id do `.desktop` do programa:

```json
"appMenus": [
  { "app": "org.mozilla.firefox.desktop", "name": "Firefox", "icon": "firefox", "items": [
    { "label": "GitHub", "icon": "internet-web-browser", "type": "url", "url": "https://github.com" },
    { "label": "Downloads", "icon": "folder-downloads", "type": "url", "url": "~/Downloads" }
  ] }
]
```

Até 6 itens no anel interno ainda ficam fáceis de mirar. Passando disso, prefira um submenu.

## Configurações

A janela de configurações abre pelo menu de aplicativos, pelo ícone da bandeja ou com `ktrackmenu`.

- **Itens do menu:** cria, edita, reordena e remove itens. Use **Testar menu** para ver o resultado
  (o teste usa a versão salva).
- **Comportamento:** atalho, segurar e soltar, iniciar com a sessão, local do arquivo de
  configuração e restaurar o padrão.
- **Aparência:**

  | Opção              | Valores                                      | No `menu.json` (`appearance`) |
  |--------------------|----------------------------------------------|-------------------------------|
  | Raio do anel       | em pixels (padrão 120)                       | `radius`                      |
  | Tamanho dos itens  | em pixels (padrão 64)                        | `itemSize`                    |
  | Formato            | círculo, cantos arredondados, quadrado       | `itemShape`: `circle`, `rounded`, `square` |
  | Cor de destaque    | qualquer cor, ou a do tema                   | `accentColor` (`""` = tema)   |
  | Números 1–9        | mostrar ou esconder                          | `showNumbers`                 |
  | Contornos          | mostrar ou esconder                          | `showBorder`                  |
  | Opacidade do anel  | 0–100 %                                      | `ringOpacity`                 |
  | Escurecer a tela   | 0–100 %                                      | `dimOpacity`                  |
  | Desfoque           | nenhum, atrás do anel, tela inteira          | `blur`: `none`, `ring`, `screen` |
  | Animações          | normais, rápidas, desligadas                 | `animation`: `normal`, `fast`, `off` |

- **Sobre:** versão, resumo de uso e informações do sistema, úteis para relatar um problema.

## O arquivo `menu.json`

Tudo fica em `~/.config/ktrackmenu/menu.json`. Você pode editá-lo à mão: o KTrackMenu percebe a
mudança e recarrega na hora, sem reiniciar.

**Levar o menu para outro computador:** copie o arquivo.

```sh
scp ~/.config/ktrackmenu/menu.json outro-pc:~/.config/ktrackmenu/
```

Exemplo completo, pequeno:

```json
{
  "version": 1,
  "appearance": { "radius": 120, "itemSize": 64, "itemShape": "circle", "blur": "ring", "ringOpacity": 75 },
  "behavior": { "holdToSelect": true },
  "items": [
    { "label": "Terminal", "icon": "utilities-terminal", "type": "app", "app": "org.kde.konsole.desktop" },
    { "label": "Arquivos", "icon": "system-file-manager", "type": "app", "app": "org.kde.dolphin.desktop" },
    { "label": "Visão geral", "icon": "view-app-grid", "type": "shortcut", "component": "/component/kwin", "shortcut": "Overview" },
    { "label": "Captura", "icon": "spectacle", "type": "command", "command": "spectacle -r" },
    { "label": "Janelas", "icon": "preferences-system-windows", "type": "windows" },
    { "label": "Mídia", "icon": "applications-multimedia", "type": "menu", "items": [
      { "label": "Tocar/Pausar", "icon": "media-playback-start", "type": "media", "action": "playpause" },
      { "label": "Próxima", "icon": "media-skip-forward", "type": "media", "action": "next" }
    ] }
  ],
  "appMenus": []
}
```

Opções que faltarem no arquivo usam o valor padrão.

## Linha de comando

```sh
ktrackmenu            # abre as configurações (e deixa o serviço rodando)
ktrackmenu --daemon   # só inicia o serviço, sem janela (é o que o "Iniciar com a sessão" usa)
ktrackmenu --toggle   # mostra ou esconde o menu (útil para ligar a outro atalho ou script)
ktrackmenu --quit     # encerra o serviço
```

Só uma cópia roda por vez: chamar `ktrackmenu` de novo conversa com a que já está aberta.

## Solução de problemas

- **O atalho não abre o menu.** Veja se o KTrackMenu está rodando (ícone na bandeja ou
  `pgrep ktrackmenu`). Confira o atalho em *Configurações do sistema → Teclado → Atalhos →
  KTrackMenu*: outro programa pode estar usando a mesma tecla.
- **Segurar e soltar não funciona.** O atalho precisa ter `Meta`, `Ctrl`, `Alt` ou `Shift`.
  Teclas como `Fn+F12` mandam "apertou" e "soltou" juntos, então não dá para segurar.
- **O desfoque não aparece.** Ative o efeito *Desfoque* em *Configurações do sistema →
  Gerenciamento de janelas → Efeitos da área de trabalho*. O efeito aparece melhor com a
  opacidade do anel abaixo de 80%.
- **Os menus por aplicativo ou as janelas abertas não aparecem.** Eles dependem de um pequeno
  script que o KTrackMenu carrega no KWin (`~/.local/share/ktrackmenu/windows.js`). Reiniciar o
  KTrackMenu carrega o script de novo.
- **O player não aparece no controle de mídia.** O player precisa suportar MPRIS (Spotify,
  Firefox, Chrome/Brave, VLC, Elisa e a maioria dos outros suportam). Para ver os players que o
  sistema enxerga: `busctl --user list | grep mpris`.
- **Algo deu errado e o menu ficou estranho.** *Comportamento → Restaurar tudo para o padrão*, ou
  apague `~/.config/ktrackmenu/menu.json` (faça uma cópia antes).

## Como funciona

```
atalho (KGlobalAccel) → MenuController → janela layer-shell em tela cheia, transparente
                                       → Overlay.qml desenha o anel em volta do cursor
item escolhido → MenuController executa: KService/KIO (apps, URLs), /bin/sh (comandos),
                 D-Bus (atalhos do KDE, MPRIS, NetworkManager, BlueZ), script do KWin (janelas)
```

| Arquivo                     | Papel                                                              |
|-----------------------------|--------------------------------------------------------------------|
| `src/main.cpp`              | ponto de entrada, linha de comando, ícone da bandeja               |
| `src/configstore.*`         | lê, grava e vigia o `menu.json`; menu padrão; iniciar com a sessão |
| `src/menucontroller.*`      | atalho global, janela do menu e execução dos itens                 |
| `src/windowtracker.*`       | app em foco e janelas abertas, via script no KWin                  |
| `src/mediaplayers.*`        | players de mídia via MPRIS                                         |
| `src/togglestates.*`        | Wi-Fi, Bluetooth, Não perturbe e Luz noturna                       |
| `src/systembridge.*`        | apps instalados, atalhos do KDE e informações do sistema           |
| `qml/Overlay.qml`           | o menu radial                                                      |
| `qml/Settings.qml`          | a janela de configurações                                          |
| `qml/ItemEditor.qml`        | o formulário de edição de um item                                  |
| `install.sh`                | instalação em qualquer distro com Plasma 6                         |

O código é comentado em português, em linguagem para iniciantes.
