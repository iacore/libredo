#!/usr/bin/fish

set task $argv[1]

if test $task -ge 4
    set mod (math $task % 4)
    switch $mod
        case 0
            redo-ifchange (math $task - 3)
        case 1
            redo-ifchange (math $task - 5)
            redo-ifchange (math $task - 3)
        case 2
            redo-ifchange (math $task - 5)
            redo-ifchange (math $task - 3)
        case 3
            redo-ifchange (math $task - 5)
    end
else
    redo-stamp < $task
end
