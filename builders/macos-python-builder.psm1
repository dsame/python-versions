using module "./builders/python-builder.psm1"

class macOSPythonBuilder : PythonBuilder {
    <#
    .SYNOPSIS
    MacOS Python builder class.

    .DESCRIPTION
    Contains methods that required to build macOS Python artifact from sources. Inherited from base NixPythonBuilder.

    .PARAMETER platform
    The full name of platform for which Python should be built.

    .PARAMETER version
    The version of Python that should be built.

    #>

    macOSPythonBuilder(
        [semver] $version,
        [string] $architecture,
        [string] $platform
    ) : Base($version, $architecture, $platform) { }

    [void] Configure() {
        <#
        .SYNOPSIS
        Execute configure script with required parameters.
        #>

        $pythonBinariesLocation = $this.GetFullPythonToolcacheLocation()
        $configureString = "./configure"
        $configureString += " --prefix=$pythonBinariesLocation"
        $configureString += " --enable-optimizations"
        $configureString += " --enable-shared"
        $configureString += " --with-lto"

        ### OS X 10.11, Apple no longer provides header files for the deprecated system version of OpenSSL.
        ### Solution is to install these libraries from a third-party package manager,
        ### and then add the appropriate paths for the header and library files to configure command.
        ### Link to documentation (https://cpython-devguide.readthedocs.io/setup/#build-dependencies)
        if ($this.Version -lt "3.7.0") {
            $env:LDFLAGS = "-L$(brew --prefix openssl)/lib"
            $env:CFLAGS = "-I$(brew --prefix openssl)/include"
        } else {
            $configureString += " --with-openssl=/usr/local/opt/openssl"
        }

        ### Compile with support of loadable sqlite extensions. Unavailable for Python 2.*
        ### Link to documentation (https://docs.python.org/3/library/sqlite3.html#sqlite3.Connection.enable_load_extension)
        if ($this.Version -ge "3.2.0") {
            $configureString += " --enable-loadable-sqlite-extensions"
            $env:LDFLAGS += " -L$(brew --prefix sqlite3)/lib"
            $env:CFLAGS += " -I$(brew --prefix sqlite3)/include"
        }

        Execute-Command -Command $configureString
    }

    [uri] GetPkgUri() {
        <#
        .SYNOPSIS
        Get base Python URI and return complete URI for Python sources.
        #>

        $base = $this.GetBaseUri()
        $versionName = $this.GetBaseVersion()
        $nativeVersion = Convert-Version -version $this.Version

        return "${base}/${versionName}/Python-${nativeVersion}-macosx10.9.pkg"
    }

    [string] Download() {
        <#
        .SYNOPSIS
        Download Python pkg. Returns the downloaded file location path.
        #>

        $pkgUri = $this.GetPkgUri()
        Write-Host "pkg URI: $pkgUri"

        $pgkFilepath = Download-File -Uri $pkgUri -OutputFolder $this.TempFolderLocation

        Write-Debug "Done; pkg location: $pkgFilepath"

        return $pgkFilepath
    }

    [void] Build() {
        <#
        .SYNOPSIS
        Instal Python artifact from pkg. 
        #>

        Write-Host "Prepare Python Hostedtoolcache location..."
        $this.PreparePythonToolcacheLocation()

        Write-Host "Download Python $($this.Version)[$($this.Architecture)] pkg..."
        $pkgLocation = $this.Download()

        Write-Host "Install Python $($this.Version)[$($this.Architecture)] pkg..."
        Execute-Command -Command "sudo installer -pkg $pkgLocation -target /"
    }
}
