set working-directory := 'data'

file := shell('cat file.txt')

@default:
  echo {{file}}
