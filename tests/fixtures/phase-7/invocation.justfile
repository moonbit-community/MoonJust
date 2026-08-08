set lists

[arg('first', long='first', pattern='[a-z]+')]
[arg('switch', short='s', flag)]
probe first switch *rest:
  echo first={{first}} switch={{switch}} rest={{rest}}

[arg('kind', long, pattern=['debug', 'release'])]
build kind:
  echo kind={{kind}}

plain required optional='fallback':
  echo required={{required}} optional={{optional}}

BASE := 'base'

[arg('selected', long, value=prefix + BASE, pattern='hello.*')]
computed prefix selected:
  echo prefix={{prefix}} selected={{selected}}

[arg('repeat', long, value=['a', 'b'], multiple)]
expanded repeat:
  echo repeat={{repeat}}
