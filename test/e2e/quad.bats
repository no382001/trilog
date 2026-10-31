#!/usr/bin/env bats

# The quad test runner.

load common

@test "quad_cli exits 0 on passing tests" {
  echo '?- 1 =:= 1.' > /tmp/trilog_pass_quad.pl
  echo '   true.' >> /tmp/trilog_pass_quad.pl
  run "$TRILOG" -e "consult('lib/quad.pl'), quad_cli('/tmp/trilog_pass_quad.pl')"
  [ "$status" -eq 0 ]
  rm -f /tmp/trilog_pass_quad.pl
}

@test "quad_cli exits 1 on failing test" {
  echo '?- 1 =:= 2.' > /tmp/trilog_fail_quad.pl
  echo '   true.' >> /tmp/trilog_fail_quad.pl
  run "$TRILOG" -e "consult('lib/quad.pl'), quad_cli('/tmp/trilog_fail_quad.pl')"
  [ "$status" -eq 1 ]
  rm -f /tmp/trilog_fail_quad.pl
}

@test "quad_cli_junit produces JUnit XML" {
  rm -rf /tmp/trilog_junit_test
  mkdir -p /tmp/trilog_junit_test
  echo '?- 1 =:= 1.' > /tmp/trilog_junit_quad.pl
  echo '   true.' >> /tmp/trilog_junit_quad.pl
  run "$TRILOG" -e "consult('lib/quad.pl'), quad_cli_junit('/tmp/trilog_junit_quad.pl', '/tmp/trilog_junit_test')"
  [ "$status" -eq 0 ]
  [ -f /tmp/trilog_junit_test/trilog_junit_quad.xml ]
  [[ "$(cat /tmp/trilog_junit_test/trilog_junit_quad.xml)" == *"<testsuite"* ]]
  [[ "$(cat /tmp/trilog_junit_test/trilog_junit_quad.xml)" == *"<testcase"* ]]
  rm -rf /tmp/trilog_junit_test /tmp/trilog_junit_quad.pl
}
