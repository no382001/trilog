# Converts TAP on stdin to a JUnit testsuite on stdout.
# usage: awk -v suite=NAME -v file=PATH -f test/tap2junit.awk
# "# ..." lines after a "not ok" become its failure text; other lines are ignored.

function esc(s) {
  gsub(/[\001-\010\013\014\016-\037]/, "", s)
  gsub(/&/, "\\&amp;", s)
  gsub(/</, "\\&lt;", s)
  gsub(/>/, "\\&gt;", s)
  gsub(/"/, "\\&quot;", s)
  return s
}

function flush() {
  if (!open) return
  if (failed)
    body = body "  <testcase classname=\"" suite "\" name=\"" esc(name) "\"><failure message=\"failed\">" esc(diag) "</failure></testcase>\n"
  else
    body = body "  <testcase classname=\"" suite "\" name=\"" esc(name) "\"/>\n"
  open = 0
}

/^(not )?ok([ \t]|$)/ {
  flush()
  open = 1
  tests++
  failed = /^not /
  if (failed) failures++
  name = $0
  sub(/^(not )?ok[ \t]*[0-9]*[ \t]*(-[ \t]*)?/, "", name)
  if (name == "") name = "test " tests
  diag = ""
  next
}

/^#/ {
  if (open && failed) {
    d = $0
    sub(/^#[ \t]?/, "", d)
    diag = diag d "\n"
  }
  next
}

END {
  flush()
  print "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
  printf "<testsuite name=\"%s\" file=\"%s\" tests=\"%d\" failures=\"%d\">\n", esc(suite), esc(file), tests, failures
  printf "%s", body
  print "</testsuite>"
}
