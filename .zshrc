#############################################################
### TITULO: myConfig
### AUTHR: dferruz
### DATE: ENE 25
#############################################################
## Terminal App
## =============
## fzf -> Find
## ncdu -> Disk used
## exa -> best ls 
## Pandoc
## cmatrix
## htop/gtop
## ranger
## nvim
## neofetch
## jp2a -> jpg 2 ascii
## awk

## Definicion de Variables
## estas definiciones sirven para visualizar con nvim en ranger
export EDITOR=nvim
export VISUAL=nvim

## alias
## filemanager
alias lf='exa -fhl --icons'
alias ld='exa -Dhl --icons'
alias la='exa -hla --icons --group-directories-first'
alias vi='nvim'
alias vim='nvim'
alias ..='cd ..'
alias gcfg='cd ~/.config'
alias gdoc='cd ~/Documentos'
alias gdwn='cd ~/Downloads'
alias gpic='cd ~/Picture'
alias grsp='cd ~/Respaldo'

## Ranger
alias rr='ranger --choosedir=$HOME/.rangerdir; LASTDIR=`cat $HOME/.rangerdir`;cd "$LASTDIR"'

## Agentes IA
alias claude='~/.local/share/applications/claude.sh'
alias leon='~/.local/share/applications/leon.sh'
alias pame='~/.local/share/applications/pame.sh'

## Monitor
# xrandr para saber cuales son los monitores activos
alias 2mnt='xrandr --output eDP1 --primary --mode 1366x768 --output HDMI1 --mode 1920x1080 --right-of eDP1' #--left-of eDP1
alias smnt='xrandr --output eDP1 --primary --mode 1366x768'

## Other
alias font='fc-list' ## fc-list | awk -F: '{print $2}' | sort |uniq 

#
# Prompt Appeariance
#

# setopt PROMPT_SUBST
## PROMPT="(%B%F{34}%n%f%b)(%B%F{8}%d%f%b)>"
## RPROMPT="(%B%F{34}%n%f%b)(%B%F{8}%d%f%b)>"

# w/starship
eval "$(starship init zsh)"
neofetch
startx

#############################################################
### REFERENCIAS
#############################################################
## Tech Craft        -  https://youtu.be/2OHrTQVlRMg
## TechHut           -  https://youtu.be/cKqsw_sAsU8
## Brodie Robertson  -  https://youtu.be/jFOso1s6PAI
##
