#Requires -Version 5.1
# Shared SQLcl launcher for the PowerShell wrappers.
#
# SQLcl builds a JLine console over its standard input at startup. Handed a
# descriptor it cannot probe -- which is what a non-interactive PowerShell
# host, a redirected stream, or the NUL device gives it -- it aborts with
# "java.io.IOException: Incorrect function" before running the script. An
# empty regular file is a standard input every platform can probe, and it
# also stops SQLcl from consuming the caller's own input.
#
# Start-Process is what allows standard input to be redirected at all:
# Windows PowerShell 5.1 has no '<' redirection operator for native commands.

function Invoke-Sqlcl {
  param(
    [Parameter(Mandatory = $true)][string[]] $Arguments,
    [Parameter(Mandatory = $true)][string] $WorkingDirectory,
    [Parameter(Mandatory = $true)][string] $StdInFile
  )

  if (-not (Test-Path -LiteralPath $StdInFile -PathType Leaf)) {
    New-Item -ItemType File -Path $StdInFile | Out-Null
  }

  # Start-Process joins -ArgumentList with spaces and does not quote, so any
  # argument holding a space (a repository path, most often) must be quoted
  # here or SQLcl receives it as several arguments.
  $quoted = @($Arguments | ForEach-Object {
    if ($_ -match '\s') { '"' + $_ + '"' } else { $_ }
  })

  $process = Start-Process -FilePath "sql" -ArgumentList $quoted `
    -WorkingDirectory $WorkingDirectory -NoNewWindow -Wait -PassThru `
    -RedirectStandardInput $StdInFile
  return $process.ExitCode
}
