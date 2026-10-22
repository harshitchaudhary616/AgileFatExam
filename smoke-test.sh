#!/bin/sh
# Static content tests for the Traffic Management Dashboard.
# Usage: smoke-test.sh [path-to-index.html]
FILE="${1:-/usr/share/nginx/html/index.html}"
FAIL=0

check() {
  if grep -q "$1" "$FILE"; then echo "PASS: $2"; else echo "FAIL: $2"; FAIL=1; fi
}

check "intersectionTable"      "Intersection table present"
check "WAIT_THRESHOLD = 120"   "120s waiting-time alert threshold"
check "Critical"               "Congestion levels defined"
check "emergencyAdvisories"    "Emergency vehicle advisories"
check "roadClosures"           "Road closure advisories"
check "filterIntersection"     "Intersection-based filtering"
check "kpiTotal"               "Total vehicles monitored"
check "kpiWorst"               "Most congested intersection"
check "suggestTiming"          "Signal timing adjustments"
check "diversionTable"         "Traffic diversion advisories"

COUNT=$(grep -c 'id: "INT-' "$FILE")
if [ "$COUNT" -ge 5 ]; then echo "PASS: $COUNT intersections (>=5)"; else echo "FAIL: only $COUNT intersections"; FAIL=1; fi

[ "$FAIL" -eq 0 ] && echo "ALL TESTS PASSED" || echo "TESTS FAILED"
exit $FAIL
