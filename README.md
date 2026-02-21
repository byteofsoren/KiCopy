# KiCopy
When working with KiCAD it happens that you downloads symbols and footprints from internet and then you need to move each symbol, footprint and 3D files manually from the source directory to where you have your repo.
This gets quite tedious fast and thus then KiCopy comes to save you.
By using the KiCopy function you don't even have to unzip the footprints KiCopy just `kicopy -t LIB_THVD151.zip`  and then the files are in your repo
The install script down below shows how to setup the repo connection.

# Synopis
```sh
kicopy -t target.zip
kicopy -t ~/tmp/componentsdir/
kicopy --target target.zip
kicopy --target ~/tmp/componentdir/
kicopy
```

## Description
The short of long form can target ether a zip file or a directory.
If the target is a zip file it extracts the following:
* Footprints
* Symbols
* 3D files
And then put them in the in to the repo named in the install.sh --repo.

## How to use:
KiCopy takes ether a directory or a zip file as a target
to copy to the repo.
Assume you have downloaded `LIB_THVD151.zip` to your system.
Then you can do the following with KiCopy:

```BASH
$ kicopy --target LIB_THVD151.zip
```
    
Then the KiCopy scripts unpacks the zip file and then moves the relevant files from the zip archive.

In the following example the folder contains zip files and then the script
unpacks all the zip files in the directory and then moves the files to the repo.

```BASH
$ kicopy --target ~/tmp/footprints
```


# Installation
Install this tool with the install script by using the flags like ether of this:

```BASH
./install.sh --repo [repo_dir] -i
./install.sh -r [repo_dir] --install
```

Where the `repo_dir` is the repo where you want to store the symbols,footprints and 3d files.
