# azure-lab

Lab automation. All operational content lives in `payload.tar.gz.age` (age-encrypted).
Workflows are thin launchers: checkout -> install age -> decrypt with the `LAB_AGE_KEY` Actions secret -> run the payload's entry script.
