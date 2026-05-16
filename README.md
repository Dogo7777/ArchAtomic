# ⚛️ Arch Atômico

Arch Linux com instalador automatizado, raiz imutável btrfs, linux-zen, KDE Plasma e Distrobox.

## O que instala

| Componente | Detalhe |
|---|---|
| **Kernel** | linux-zen + headers |
| **Filesystem** | btrfs com 12 subvolumes, raiz `ro` (imutável) |
| **Desktop** | KDE Plasma + SDDM |
| **Containers** | Distrobox + Arch-base (pacman/yay) + subsistema (Ubuntu/apt) |
| **Shell** | zsh + Oh My Zsh + Powerlevel10k |
| **Task runner** | just (equivalente ao ujust do Bazzite) |
| **Áudio** | PipeWire + WirePlumber |
| **zram** | zstd, metade da RAM |
| **Otimizações** | sysctl bbr/cake, intel_powerclamp blacklist, ananicy-cpp |
| **Snapshots** | snapper + snap-pac |

## Subvolumes btrfs

```
@             → /              (ro — imutável)
@home         → /home
@var          → /var
@log          → /var/log
@snapshots    → /.snapshots
@flatpak      → /var/lib/flatpak
@opt          → /opt
@usr_local    → /usr/local
@cache        → cache do pacman
@pkg_cache    → cache de pacotes
@virt         → máquinas virtuais
@containers   → containers distrobox
@etc          → bind mounts persistentes
```

## Instalação

### Requisitos
- Boot em modo **UEFI**
- Conexão com internet
- Disco com no mínimo **40GB**

### Passo a passo

```bash
# 1. Boot no Arch Linux Live ISO
# 2. Conecte o Wi-Fi (se necessário):
iwctl station wlan0 connect "Nome da Rede"

# 3. Baixe e rode o instalador:
curl -sL https://raw.githubusercontent.com/Dogo7777/ArchAtomic/main/install.sh -o install.sh
bash install.sh
```

O instalador pergunta:
- Qual disco usar
- Nome de usuário e senha
- Hostname

O restante é automático (~15 minutos).

### Primeiro boot

Ao entrar no KDE pela primeira vez, um terminal abrirá automaticamente e:
1. Criará os containers `Arch-base` e `subsistema`
2. Aplicará os dotfiles completos (KDE, zsh, etc.)
3. Restaurará os pacotes dos containers

## Comandos úteis pós-instalação

```bash
just           # lista todos os comandos
just pac pkg   # instala via pacman (Arch-base)
just aur pkg   # instala via yay (AUR)
just apt pkg   # instala via apt (subsistema)
just unlock    # monta raiz em RW para modificações
just lock      # volta raiz para RO
just update-all# atualiza todos os containers
just status    # status dos containers distrobox
```

## Estrutura do repositório

```
arch-atomico/
├── install.sh          ← instalador principal
├── setup/
│   ├── 01-base.sh      ← partições + base
│   ├── 02-kernel.sh    ← linux-zen
│   ├── 03-kde.sh       ← plasma + temas
│   ├── 04-distrobox.sh ← containers
│   ├── 05-system.sh    ← grub, sysctl, zram
│   └── 06-dotfiles.sh  ← dotfiles
└── README.md
```

## AMD vs Intel

O instalador usa `intel-ucode` por padrão. Para AMD edite o `install.sh`:

```bash
# Linha ~160, troque:
intel-ucode
# Por:
amd-ucode
```

## Créditos

Inspirado por [Bazzite](https://bazzite.gg), [CachyOS](https://cachyos.org) e [EndeavourOS](https://endeavouros.com).
