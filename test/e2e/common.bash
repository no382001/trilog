TRILOG="./trilog"

succeeded() {
  [[ "$output" != *"   false."* && "$output" != *"uncaught exception"* && "$output" != *"parse error"* ]]
}

answers() {
  if succeeded; then
    echo $(($(echo "$output" | grep -c '^;  ') + 1))
  else
    echo 0
  fi
}
