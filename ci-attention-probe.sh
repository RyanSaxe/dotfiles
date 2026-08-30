#!/bin/sh
# Throwaway probe for the GitHub attention observer's CI detection path.
# Deliberately trips shellcheck (SC2045, SC2086) so `prek run --all-files`
# fails and the PR goes red. Delete this file and its branch once the
# observer has been seen to pick the failure up.
for f in $(ls); do
  echo $f
done
