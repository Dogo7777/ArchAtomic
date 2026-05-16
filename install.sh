#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
# install.sh — Arch Atômico Installer
#
# Roda a partir do Live ISO oficial do Arch Linux.
# Instala e configura tudo automaticamente:
#   • Particionamento btrfs com subvolumes idênticos ao setup original
#   • Raiz imutável (ro), home/var/log/flatpak/opt/usr_local (rw)
#   • linux-zen + headers
#   • KDE Plasma
#   • GRUB + otimizações
#   • zram, sysctl, blacklist intel_powerclamp
#   • Distrobox + containers Arch-base e subsistema
#   • Dotfiles do usuário (zsh, just, KDE, serviços)
#
# Uso (no live ISO):
#   curl -sL https://raw.githubusercontent.com/SEU_USER/arch-atomico/main/install.sh | bash
#   ou:
#   bash install.sh
# ══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# ── Cores ─────────────────────────────────────────────────────────────────────
B='\033[38;5;39m'; G='\033[38;5;82m'; Y='\033[38;5;220m'
R='\033[0m'; W='\033[1;37m'; E='\033[1;31m'; D='\033[2m'

info()    { echo -e "${B}  →${R} $*"; }
success() { echo -e "${G}  ✔${R} $*"; }
warn()    { echo -e "${Y}  ⚠${R} $*"; }
error()   { echo -e "${E}  ✖${R} $*"; exit 1; }
ask()     { echo -e "${W}  ?${R} $*"; }
section() {
    echo -e "\n${B}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${R}"
    echo -e "${W}  $*${R}"
    echo -e "${B}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${R}\n"
}

# ══════════════════════════════════════════════════════════════════════════════
# CONFIGURAÇÃO — editável antes de rodar
# ══════════════════════════════════════════════════════════════════════════════

GITHUB_USER="SEU_USUARIO"          # seu usuário no GitHub
DOTFILES_REPO="dotfiles"           # nome do repositório de dotfiles
HOSTNAME_DEFAULT="arch-atomico"
LOCALE="pt_BR.UTF-8"
KEYMAP="br-abnt2"
TIMEZONE="America/Sao_Paulo"
USERNAME_DEFAULT="luis"

# ══════════════════════════════════════════════════════════════════════════════
# BANNER
# ══════════════════════════════════════════════════════════════════════════════

clear
echo -e "
${B}  ╔═══════════════════════════════════════════════════╗
  ║          Arch Atômico — Instalador v1.0           ║
  ║                                                   ║
  ║  • Btrfs imutável  • linux-zen  • KDE Plasma      ║
  ║  • Distrobox       • Dotfiles   • Otimizações     ║
  ╚═══════════════════════════════════════════════════╝${R}
"

# ══════════════════════════════════════════════════════════════════════════════
# VERIFICAÇÕES PRÉ-INSTALAÇÃO
# ══════════════════════════════════════════════════════════════════════════════

[[ $EUID -ne 0 ]] && error "Rode como root no Live ISO: sudo bash install.sh"

if ! ping -c 1 archlinux.org &>/dev/null; then
    error "Sem internet. Conecte e tente novamente."
fi

if [ ! -d /sys/firmware/efi ]; then
    error "Sistema não está em modo UEFI. Este instalador requer UEFI."
fi

# ══════════════════════════════════════════════════════════════════════════════
# COLETA DE INFORMAÇÕES
# ══════════════════════════════════════════════════════════════════════════════

section "CONFIGURAÇÃO DA INSTALAÇÃO"

# Lista discos disponíveis
echo -e "${W}  Discos disponíveis:${R}\n"
lsblk -d -o NAME,SIZE,MODEL | grep -v "loop\|sr"
echo ""

ask "Em qual disco instalar? (ex: sda, nvme0n1, sdb)"
read -rp "  Disco: " DISK_NAME
DISK="/dev/$DISK_NAME"

[[ ! -b "$DISK" ]] && error "Disco $DISK não encontrado."

ask "Nome de usuário? [padrão: $USERNAME_DEFAULT]"
read -rp "  Usuário: " USERNAME
USERNAME="${USERNAME:-$USERNAME_DEFAULT}"

ask "Nome do host? [padrão: $HOSTNAME_DEFAULT]"
read -rp "  Hostname: " HOSTNAME
HOSTNAME="${HOSTNAME:-$HOSTNAME_DEFAULT}"

ask "Senha do usuário $USERNAME:"
read -rsp "  Senha: " USER_PASS; echo ""
ask "Confirme a senha:"
read -rsp "  Confirmar: " USER_PASS2; echo ""
[[ "$USER_PASS" != "$USER_PASS2" ]] && error "Senhas não conferem."

ask "Senha do root:"
read -rsp "  Senha root: " ROOT_PASS; echo ""

# Confirma antes de destruir o disco
echo ""
echo -e "${E}  ⚠  ATENÇÃO: O disco $DISK será completamente apagado!${R}"
echo -e "     Tamanho: $(lsblk -d -n -o SIZE $DISK)"
echo ""
read -rp "  Digite CONFIRMAR para continuar: " CONF
[[ "$CONF" != "CONFIRMAR" ]] && echo "Cancelado." && exit 0

# ══════════════════════════════════════════════════════════════════════════════
# ETAPA 1 — PARTICIONAMENTO
# ══════════════════════════════════════════════════════════════════════════════

section "ETAPA 1/9 — Particionamento"

info "Particionando $DISK..."

# Determina prefixo de partição (sda → sda1, nvme0n1 → nvme0n1p1)
if [[ "$DISK" == *"nvme"* ]] || [[ "$DISK" == *"mmcblk"* ]]; then
    PART_PREFIX="${DISK}p"
else
    PART_PREFIX="${DISK}"
fi

EFI_PART="${PART_PREFIX}1"
ROOT_PART="${PART_PREFIX}2"

# Cria tabela GPT + partições
parted -s "$DISK" \
    mklabel gpt \
    mkpart EFI  fat32  1MiB   513MiB \
    mkpart ROOT btrfs  513MiB 100% \
    set 1 esp on

# Formata
mkfs.fat -F32 -n EFI "$EFI_PART"
mkfs.btrfs -f -L "arch-atomico" "$ROOT_PART"

success "Disco particionado: EFI=$EFI_PART  ROOT=$ROOT_PART"

# UUID do ROOT para usar no fstab
ROOT_UUID=$(blkid -s UUID -o value "$ROOT_PART")
EFI_UUID=$(blkid -s UUID -o value "$EFI_PART")
success "UUID ROOT: $ROOT_UUID"
success "UUID EFI:  $EFI_UUID"

# ══════════════════════════════════════════════════════════════════════════════
# ETAPA 2 — SUBVOLUMES BTRFS
# ══════════════════════════════════════════════════════════════════════════════

section "ETAPA 2/9 — Subvolumes btrfs"

# Monta temporariamente para criar subvolumes
mount "$ROOT_PART" /mnt

info "Criando subvolumes..."

# Subvolumes principais (espelho exato do seu setup)
SUBVOLS=(
    "@"           # raiz — será montada como ro (imutável)
    "@home"       # dados do usuário
    "@var"        # /var completo (rw)
    "@log"        # /var/log separado
    "@snapshots"  # snapshots do snapper
    "@flatpak"    # /var/lib/flatpak
    "@opt"        # /opt
    "@usr_local"  # /usr/local
    "@cache"      # cache do pacman
    "@pkg_cache"  # cache de pacotes
    "@virt"       # máquinas virtuais
    "@containers" # containers (distrobox)
    "@etc"        # /etc persistente (para bind mounts)
)

for sv in "${SUBVOLS[@]}"; do
    btrfs subvolume create "/mnt/$sv"
    success "Subvolume: $sv"
done

# Cria estrutura de persist para os bind mounts (ananicy.d, xml)
mkdir -p /mnt/@etc/xml
mkdir -p /mnt/@etc/ananicy.d

umount /mnt
success "Subvolumes criados"

# ══════════════════════════════════════════════════════════════════════════════
# ETAPA 3 — MONTAGEM DO SISTEMA
# ══════════════════════════════════════════════════════════════════════════════

section "ETAPA 3/9 — Montagem"

# Opções comuns btrfs (idênticas ao seu fstab)
BTRFS_OPTS="rw,noatime,ssd,discard=async,space_cache=v2,compress=zstd:1"
BTRFS_OPTS_RO="ro,noatime,ssd,discard=async,space_cache=v2,compress=zstd:1"

info "Montando subvolumes..."

# Raiz — ro (imutável) durante a instalação usamos rw, depois trocamos
mount -o "${BTRFS_OPTS},subvol=@" "$ROOT_PART" /mnt

# Cria pontos de montagem
mkdir -p /mnt/{home,var,opt,boot/efi,.snapshots}
mkdir -p /mnt/var/{log,lib/flatpak,tmp}
mkdir -p /mnt/usr/local
mkdir -p /mnt/etc/{xml,ananicy.d}

# Monta subvolumes
mount -o "${BTRFS_OPTS},subvol=@home"      "$ROOT_PART" /mnt/home
mount -o "${BTRFS_OPTS},subvol=@var"       "$ROOT_PART" /mnt/var
mount -o "${BTRFS_OPTS},subvol=@log"       "$ROOT_PART" /mnt/var/log
mount -o "${BTRFS_OPTS},subvol=@snapshots" "$ROOT_PART" /mnt/.snapshots
mount -o "${BTRFS_OPTS},subvol=@flatpak"   "$ROOT_PART" /mnt/var/lib/flatpak
mount -o "${BTRFS_OPTS},subvol=@opt"       "$ROOT_PART" /mnt/opt
mount -o "${BTRFS_OPTS},subvol=@usr_local" "$ROOT_PART" /mnt/usr/local
mount "$EFI_PART" /mnt/boot/efi

success "Todos os subvolumes montados"

# ══════════════════════════════════════════════════════════════════════════════
# ETAPA 4 — INSTALAÇÃO BASE
# ══════════════════════════════════════════════════════════════════════════════

section "ETAPA 4/9 — Sistema base"

info "Instalando pacotes base (pacstrap)..."

pacstrap -K /mnt \
    base base-devel \
    linux-zen linux-zen-headers \
    linux-firmware \
    btrfs-progs \
    grub efibootmgr \
    networkmanager \
    sudo git curl wget \
    zsh zsh-completions \
    neovim \
    fastfetch \
    pipewire pipewire-pulse pipewire-alsa wireplumber \
    plasma-meta sddm \
    konsole dolphin \
    flatpak \
    distrobox podman \
    just \
    stow \
    snapper snap-pac \
    reflector \
    zram-generator \
    ananicy-cpp \
    power-profiles-daemon \
    intel-ucode \   # troque por amd-ucode se for AMD
    xdg-user-dirs

success "Sistema base instalado"

# ══════════════════════════════════════════════════════════════════════════════
# ETAPA 5 — FSTAB
# ══════════════════════════════════════════════════════════════════════════════

section "ETAPA 5/9 — fstab"

info "Gerando fstab..."

cat > /mnt/etc/fstab << FSTAB
# Arch Atômico — fstab
# Gerado pelo install.sh em $(date)

# ROOT (imutável — ro)
UUID=$ROOT_UUID  /               btrfs  ro,noatime,ssd,discard=async,space_cache=v2,compress=zstd:1,subvol=@           0 0

# HOME
UUID=$ROOT_UUID  /home           btrfs  rw,noatime,ssd,discard=async,space_cache=v2,compress=zstd:1,subvol=@home       0 0

# VAR
UUID=$ROOT_UUID  /var            btrfs  rw,noatime,ssd,discard=async,space_cache=v2,compress=zstd:1,subvol=@var        0 0

# LOGS
UUID=$ROOT_UUID  /var/log        btrfs  rw,noatime,ssd,discard=async,space_cache=v2,compress=zstd:1,subvol=@log        0 0

# SNAPSHOTS
UUID=$ROOT_UUID  /.snapshots     btrfs  rw,noatime,ssd,discard=async,space_cache=v2,subvol=@snapshots                  0 0

# FLATPAK
UUID=$ROOT_UUID  /var/lib/flatpak btrfs rw,noatime,ssd,discard=async,space_cache=v2,compress=zstd:1,subvol=@flatpak   0 0

# OPT
UUID=$ROOT_UUID  /opt            btrfs  rw,noatime,ssd,discard=async,space_cache=v2,compress=zstd:1,subvol=@opt        0 0

# USR/LOCAL
UUID=$ROOT_UUID  /usr/local      btrfs  rw,noatime,ssd,discard=async,space_cache=v2,compress=zstd:1,subvol=@usr_local  0 0

# EFI
UUID=$EFI_UUID   /boot/efi       vfat   rw,relatime,fmask=0022,dmask=0022                                              0 2

# TMP (RAM)
tmpfs            /tmp            tmpfs  defaults,noatime,mode=1777,size=4G  0 0
tmpfs            /var/tmp        tmpfs  defaults,noatime,mode=1777,size=2G  0 0

# BIND MOUNTS (persistência em /var)
/var/persist/etc/xml       /etc/xml       none  bind,nofail,x-systemd.requires=/var  0 0
/var/persist/etc/ananicy.d /etc/ananicy.d none  bind,nofail,x-systemd.requires=/var  0 0
FSTAB

success "fstab gerado"

# ══════════════════════════════════════════════════════════════════════════════
# ETAPA 6 — CONFIGURAÇÃO DO SISTEMA (chroot)
# ══════════════════════════════════════════════════════════════════════════════

section "ETAPA 6/9 — Configuração do sistema"

info "Entrando no chroot..."

# Passa variáveis para o chroot
arch-chroot /mnt /bin/bash << CHROOT
set -euo pipefail

# ── Locale / Timezone / Hostname ──────────────────────────────────────────────
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

sed -i 's/#$LOCALE/$LOCALE/' /etc/locale.gen
echo "LANG=$LOCALE" > /etc/locale.conf
locale-gen

echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf
echo "$HOSTNAME" > /etc/hostname

cat > /etc/hosts << EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
EOF

# ── Senhas ────────────────────────────────────────────────────────────────────
echo "root:$ROOT_PASS" | chpasswd

# ── Usuário ───────────────────────────────────────────────────────────────────
useradd -m -G wheel,audio,video,storage,optical,network -s /bin/zsh "$USERNAME"
echo "$USERNAME:$USER_PASS" | chpasswd
echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers

# ── mkinitcpio ────────────────────────────────────────────────────────────────
# Hooks otimizados para btrfs + systemd
sed -i 's/^HOOKS=.*/HOOKS=(base systemd autodetect modconf kms keyboard sd-vconsole block filesystems fsck)/' /etc/mkinitcpio.conf
# Adiciona btrfs aos módulos
sed -i 's/^MODULES=.*/MODULES=(btrfs)/' /etc/mkinitcpio.conf
mkinitcpio -P

# ── GRUB ─────────────────────────────────────────────────────────────────────
cat > /etc/default/grub << 'GRUBEOF'
GRUB_DEFAULT=0
GRUB_TIMEOUT=3
GRUB_DISTRIBUTOR="Arch Atômico"
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash loglevel=3 rd.udev.log_priority=3 vt.global_cursor_default=0 nowatchdog"
GRUB_CMDLINE_LINUX=""
GRUB_PRELOAD_MODULES="part_gpt part_msdos"
GRUB_TERMINAL_INPUT=console
GRUB_GFXMODE=auto
GRUB_GFXPAYLOAD_LINUX=keep
GRUB_DISABLE_RECOVERY=true
GRUBEOF

grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id="Arch Atômico"
grub-mkconfig -o /boot/grub/grub.cfg

# ── Blacklist intel_powerclamp ────────────────────────────────────────────────
cat > /etc/modprobe.d/blacklist-powerclamp.conf << 'EOF'
# Desabilita throttling térmico agressivo da Intel
# que causa stuttering em jogos e cargas pesadas
blacklist intel_powerclamp
EOF

# ── sysctl — otimizações ──────────────────────────────────────────────────────
cat > /etc/sysctl.d/99-arch-atomico.conf << 'EOF'
# Arch Atômico — Otimizações de kernel

# Memória / VM
vm.swappiness=10
vm.dirty_ratio=15
vm.dirty_background_ratio=5
vm.vfs_cache_pressure=50

# Rede
net.core.netdev_max_backlog=16384
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_congestion_control=bbr
net.core.default_qdisc=cake

# Segurança
kernel.kptr_restrict=2
kernel.dmesg_restrict=1

# Performance
kernel.nmi_watchdog=0
kernel.unprivileged_userns_clone=1
EOF

# ── zram ─────────────────────────────────────────────────────────────────────
cat > /etc/systemd/zram-generator.conf << 'EOF'
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
swap-priority = 100
fs-type = swap
EOF

# ── Serviços ──────────────────────────────────────────────────────────────────
systemctl enable NetworkManager
systemctl enable sddm
systemctl enable fstrim.timer
systemctl enable reflector.timer
systemctl enable ananicy-cpp
systemctl enable power-profiles-daemon
systemctl enable systemd-zram-setup@zram0.service

# ── Diretórios de bind mount ──────────────────────────────────────────────────
mkdir -p /var/persist/etc/xml
mkdir -p /var/persist/etc/ananicy.d

# ── XDG dirs do usuário ───────────────────────────────────────────────────────
sudo -u $USERNAME xdg-user-dirs-update

CHROOT

success "Sistema configurado no chroot"

# ══════════════════════════════════════════════════════════════════════════════
# ETAPA 7 — DOTFILES
# ══════════════════════════════════════════════════════════════════════════════

section "ETAPA 7/9 — Dotfiles"

USER_HOME="/mnt/home/$USERNAME"

if [[ "$GITHUB_USER" != "SEU_USUARIO" ]]; then
    info "Clonando dotfiles de github.com/$GITHUB_USER/$DOTFILES_REPO..."
    arch-chroot /mnt sudo -u "$USERNAME" bash -c "
        git clone https://github.com/$GITHUB_USER/$DOTFILES_REPO.git ~/dotfiles
        cd ~/dotfiles
        mkdir -p ~/.local/bin
        # Stow básico — zsh e just (KDE precisa de sessão gráfica)
        stow --target=\$HOME --dir=\$HOME/dotfiles zsh just 2>/dev/null || true
    "
    success "Dotfiles clonados e symlinks básicos aplicados"
    warn "KDE será aplicado no primeiro login via ~/.config/autostart/"
else
    warn "GITHUB_USER não configurado — pulando dotfiles"
    warn "Configure e rode: bash ~/dotfiles/scripts/stow-all.sh"
fi

# ── Oh My Zsh + Powerlevel10k ──────────────────────────────────────────────────
info "Instalando Oh My Zsh + Powerlevel10k..."
arch-chroot /mnt sudo -u "$USERNAME" bash -c '
    RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git \
        ~/.oh-my-zsh/custom/themes/powerlevel10k
    git clone https://github.com/zsh-users/zsh-autosuggestions \
        ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions
    git clone https://github.com/zsh-users/zsh-syntax-highlighting \
        ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting
' 2>/dev/null
success "Oh My Zsh + P10k instalados"

# ══════════════════════════════════════════════════════════════════════════════
# ETAPA 8 — DISTROBOX + CONTAINERS
# ══════════════════════════════════════════════════════════════════════════════

section "ETAPA 8/9 — Distrobox"

# Cria script de primeiro boot que configura os containers
# (não podemos criar containers agora pois precisamos de sessão de usuário)
cat > "/mnt/home/$USERNAME/.config/autostart/arch-atomico-firstboot.desktop" << EOF
[Desktop Entry]
Type=Application
Name=Arch Atômico — Primeiro Boot
Exec=konsole -e bash /home/$USERNAME/.firstboot.sh
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF

cat > "/mnt/home/$USERNAME/.firstboot.sh" << FIRSTBOOT
#!/usr/bin/env bash
# Roda automaticamente no primeiro login via KDE autostart
set -euo pipefail

DOTFILES="\$HOME/dotfiles"

echo "=== Arch Atômico — Configuração do Primeiro Boot ==="
echo ""

# Cria containers distrobox
echo "→ Criando container Arch-base..."
distrobox create --name Arch-base --image archlinux:latest --yes

echo "→ Criando container subsistema (Ubuntu)..."
distrobox create --name subsistema --image ubuntu:24.04 --yes

# Inicia containers para configuração inicial
echo "→ Inicializando Arch-base..."
distrobox enter Arch-base -- bash -c "
    sudo pacman -Syu --noconfirm
    sudo pacman -S --noconfirm yay base-devel git
"

echo "→ Inicializando subsistema..."
distrobox enter subsistema -- bash -c "
    sudo apt-get update -qq
    sudo apt-get install -y curl wget git
"

# Aplica o restante dos dotfiles (KDE, serviços)
if [ -d "\$DOTFILES" ]; then
    echo "→ Aplicando dotfiles completos..."
    bash "\$DOTFILES/scripts/stow-all.sh" 2>/dev/null || true

    # Restaura pacotes dos containers se existirem listas
    if [ -f "\$DOTFILES/packages/pkglist-arch-base.txt" ]; then
        echo "→ Restaurando pacotes do Arch-base..."
        PKGS=\$(grep -vE "^(base|linux|filesystem)" \
            "\$DOTFILES/packages/pkglist-arch-base.txt" | tr '\n' ' ')
        distrobox enter Arch-base -- sudo pacman -S --needed --noconfirm \$PKGS 2>/dev/null || true
    fi

    if [ -f "\$DOTFILES/packages/pkglist-subsistema.txt" ]; then
        echo "→ Restaurando pacotes do subsistema..."
        PKGS=\$(grep -vE "^(base-files|bash|apt|dpkg)" \
            "\$DOTFILES/packages/pkglist-subsistema.txt" | tr '\n' ' ')
        distrobox enter subsistema -- sudo apt-get install -y \$PKGS 2>/dev/null || true
    fi
fi

echo ""
echo "✔ Configuração concluída! Removendo script de primeiro boot..."
rm -f "\$HOME/.config/autostart/arch-atomico-firstboot.desktop"
rm -f "\$HOME/.firstboot.sh"
echo "✔ Reinicie o KDE para aplicar as configurações."
FIRSTBOOT

chmod +x "/mnt/home/$USERNAME/.firstboot.sh"
arch-chroot /mnt chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/.config" \
    "/home/$USERNAME/.firstboot.sh"

success "Script de primeiro boot criado"

# ══════════════════════════════════════════════════════════════════════════════
# ETAPA 9 — RAIZ IMUTÁVEL + FINALIZAÇÃO
# ══════════════════════════════════════════════════════════════════════════════

section "ETAPA 9/9 — Raiz imutável + Finalização"

info "Tornando a raiz somente-leitura (imutável)..."

# Define atributo de imutabilidade no subvolume @ via btrfs property
# A montagem ro no fstab já garante isso, mas o atributo adiciona uma camada extra
# btrfs property set /mnt ro true  ← NÃO fazemos aqui pois impossibilita o chroot
# A flag ro no fstab é suficiente e já está configurada

success "Raiz configurada como ro no fstab ✔"

# Script de unlock/lock já vem do dotfiles (.justfile: just unlock / just lock)
info "Verificando instalação..."

# Verifica itens críticos
CHECKS=(
    "/mnt/boot/efi/EFI"
    "/mnt/boot/grub/grub.cfg"
    "/mnt/etc/fstab"
    "/mnt/etc/mkinitcpio.conf"
    "/mnt/home/$USERNAME"
)

ALL_OK=true
for check in "${CHECKS[@]}"; do
    if [ -e "$check" ]; then
        success "OK: $check"
    else
        warn "Não encontrado: $check"
        ALL_OK=false
    fi
done

# ── Desmonta tudo ─────────────────────────────────────────────────────────────
info "Desmontando..."
umount -R /mnt
success "Desmontado"

# ══════════════════════════════════════════════════════════════════════════════
# RESUMO FINAL
# ══════════════════════════════════════════════════════════════════════════════

echo ""
echo -e "${B}╔═══════════════════════════════════════════════════════╗${R}"
echo -e "${B}║${R}   ${G}✔  Arch Atômico instalado com sucesso!${R}             ${B}║${R}"
echo -e "${B}╚═══════════════════════════════════════════════════════╝${R}"
echo ""
echo -e "  ${W}Disco:${R}     $DISK"
echo -e "  ${W}Usuário:${R}   $USERNAME"
echo -e "  ${W}Hostname:${R}  $HOSTNAME"
echo -e "  ${W}Kernel:${R}    linux-zen"
echo -e "  ${W}Raiz:${R}      btrfs ro (imutável)"
echo ""
echo -e "  ${W}Subvolumes criados:${R}"
echo -e "  @  @home  @var  @log  @snapshots  @flatpak"
echo -e "  @opt  @usr_local  @cache  @virt  @containers  @etc"
echo ""
echo -e "  ${Y}Remova o pendrive e reinicie:${R}"
echo -e "  ${B}reboot${R}"
echo ""
echo -e "  ${D}No primeiro login o KDE abrirá um terminal${R}"
echo -e "  ${D}configurando os containers Distrobox automaticamente.${R}"
echo ""
