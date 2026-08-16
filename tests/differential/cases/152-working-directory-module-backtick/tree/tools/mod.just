set working-directory := 'data'

file := `cat file.txt`

@default:
  echo {{file}}
