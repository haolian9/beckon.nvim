a fuzzy matching picker


## motivation
i need a lightweight fuzzy matching picker in nvim, to replace fzf in **some** usecases:
* buffers, arglist
* lsp document/workspace symbol
* ui.select
* ...

## status
* WIP
* the use of ffi may crash nvim

## prerequisites
* zig 0.11
* nvim 0.10.*
* haolian9/infra.nvim

## usage
* `zig build -Doptimize=ReleaseSafe`
* `require'beckon'.buffers()`

## credits
[natecraddock/zf](https://github.com/natecraddock/zf) laid the foundation of this plugin.
