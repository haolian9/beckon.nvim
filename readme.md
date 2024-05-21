an opinionated fuzzy matching picker


## motivation
i need a lightweight fuzzy matching picker in nvim to replace fzf in **some specific** usecases

## design choices, limits, goals/non-goals
* no cache for dataset
    * for large datasets (say 1 million), consider using fzf
    * may suffer the limits of nvim buffer: memory consumption, highlight, undo history, and something i dont know yet
* no fancy UI
* no seperated windows for user input and matched result
    * and unexpected user operations to buffers may cause troubles likely
* default query
* clear the default query when user input something new
* multiple actions for the picked entry
    * n_{i,o,v,t}, i_c-{m,o,/,t}
    * depends on the source/provider, of course
* no multiple selection/picking
* no fzf --nth nor conceal
* since it's a buffer, you can:
    * have vim modes
    * use motion plugins

## status
* just works
* the use of ffi may crash nvim
* speed, performance: i have not put too much efforts on it

## todo
* [ ] to replace ui.select
* [ ] highlight token

## sources
* [x] buffers
* [x] arglist
* [x] digraphs
* [x] windows
* [ ] lsp document symbol
* [ ] lsp workspace symbol

## prerequisites
* zig 0.12
* nvim 0.10.*
* haolian9/infra.nvim

## usage
* `zig build -Doptimize=ReleaseSafe`
* `require'beckon'.buffers()`

## credits
[natecraddock/zf](https://github.com/natecraddock/zf) laid the foundation of this plugin.
