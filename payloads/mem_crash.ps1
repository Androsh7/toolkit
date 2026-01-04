write-output $(Get-random) >> cpfile
while ($TRUE) {get-content cpfile | write-output >> cpfile}