Example "project" to test the time complexity of redo.

Run `redo-ifchange 100` to test cache.
Run `touch 0` to invalidate cache.

## Benchmark trace

Verdict: it's O(n).

```
❯ for n in 10 100 500 1000 2000
      ./bench $n
  end

________________________________________________________
Executed in  397.20 millis    fish           external
   usr time  273.70 millis  147.00 micros  273.55 millis
   sys time   71.70 millis   53.00 micros   71.65 millis


________________________________________________________
Executed in    3.59 secs    fish           external
   usr time    2.85 secs  158.00 micros    2.85 secs
   sys time    0.72 secs   43.00 micros    0.72 secs


________________________________________________________
Executed in   18.05 secs    fish           external
   usr time   14.30 secs  179.00 micros   14.30 secs
   sys time    3.82 secs   25.00 micros    3.82 secs


________________________________________________________
Executed in   36.43 secs    fish           external
   usr time   28.70 secs  176.00 micros   28.70 secs
   sys time    7.69 secs   52.00 micros    7.69 secs


________________________________________________________
Executed in   77.38 secs    fish           external
   usr time   59.48 secs  150.00 micros   59.48 secs
   sys time   16.69 secs   50.00 micros   16.69 secs

```
