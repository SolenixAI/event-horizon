#!/usr/bin/env bash
# Source this file to ensure developer and agent toolchains are on PATH:
#   source scripts/env.sh

case ":$PATH:" in
  *":/opt/homebrew/bin:"*) ;;
  *)
    if [ -d "/opt/homebrew/bin" ]; then
      export PATH="/opt/homebrew/bin:$PATH"
    fi
    ;;
esac

case ":$PATH:" in
  *":$HOME/.cargo/bin:"*) ;;
  *)
    if [ -d "$HOME/.cargo/bin" ]; then
      export PATH="$HOME/.cargo/bin:$PATH"
    fi
    ;;
esac

:
