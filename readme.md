an opinionated fuzzy picker

https://github.com/haolian9/zongzi/assets/6236829/34283b3a-f9dc-44fc-aaad-5b4fcda2785e


## motivation
i need a lightweight fuzzy matching picker in nvim to replace fzf in **some specific** usecases

## design choices, limits, goals/non-goals
* no cache for dataset
    * for large datasets (say 1 million), consider using fzf
    * may suffer the limits of nvim buffer: memory consumption, highlight, undo history, and something i dont know yet
        * note: the undo history of beckon buffers are disabled
* no fancy UI
* no seperated windows for user input and matched result
    * and unexpected user operations to buffers may cause troubles likely
* default query / placeholder
* clear the default query when user input something new
* multiple actions for the picked entry
    * n_{i,o,v,t}, i_c-{m,o,/,t}
    * depends on the source/provider, of course
* no multiple selection/picking
* no fzf --nth nor conceal
* since it's a buffer, you can:
    * have vim modes
    * use motion plugins
* an impl of vim.ui.select

## status
* just works
* the use of ffi may crash nvim
* feature complete
* performance can be bad

## efforts on efficiency
* incremental matching results
* load partial results to the buffer
* merge update events happened in a period
* minimal lines to add highlights of matched token
    * yet, nvim_set_decoration_provider is not being used.

## sources
* [x] buffers
* [x] arglist
* [x] digraphs
* [x] emojis
* [x] windows
* [ ] lsp document symbol
* [x] cmds/history

## prerequisites
* zig 0.12
* nvim 0.10.*
* haolian9/infra.nvim

## usage
* `zig build -Doptimize=ReleaseSafe`
* `require'beckon'.buffers()`

## credits
[natecraddock/zf](https://github.com/natecraddock/zf) laid the foundation of this plugin.
