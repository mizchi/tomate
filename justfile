# tomate - Multi-agent orchestration engine

target := "native"
bin := "app"

default: check test

fmt:
    moon fmt

check:
    moon check --deny-warn --target {{target}}

test:
    moon test --target {{target}}

test-update:
    moon test --update --target {{target}}

run *args:
    moon run src/cmd/{{bin}} --target native -- {{args}}

build:
    moon build --release --target native src/cmd/{{bin}}

clean:
    moon clean
