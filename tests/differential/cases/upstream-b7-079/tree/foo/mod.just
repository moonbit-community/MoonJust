set dotenv-load := false
foo:
 @echo $ROOT_KEY ${SUB_KEY:-unset}
