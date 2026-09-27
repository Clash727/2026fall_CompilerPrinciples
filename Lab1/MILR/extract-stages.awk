# Extract complete module dumps; retain source line ranges in a TSV index.
function flush(   file) {
  if (!active) return
  sub(/\n+$/, "", body)
  file = sprintf("%04d-%s-%s.mlir", serial, tolower(phase), pass)
  print body > (out "/snapshots/" file)
  close(out "/snapshots/" file)
  printf "%d\t%s\t%s\t%d\t%d\t%s\n", serial, phase, pass, first, last, file >> (out "/snapshots.tsv")
}
BEGIN {
  print "snapshot\tphase\tpass\tlog_start\tlog_end\tfile" > (out "/snapshots.tsv")
}
/^\/\/ -----\/\/ IR Dump (Before|After) / {
  flush()
  serial++
  phase = ($0 ~ /IR Dump Before /) ? "Before" : "After"
  pass = $0
  sub(/^.*IR Dump (Before|After) [^(]*\(/, "", pass)
  sub(/\).*$/, "", pass)
  first = NR
  last = NR
  body = ""
  active = 1
  next
}
active { body = body $0 "\n"; last = NR }
END { flush() }
