package main

import (
	"flag"
	"fmt"
	"os"

	"github.com/SA-MP-Android/Plugin-Tools/internal/plugin"
)

var version = "dev"

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		os.Exit(1)
	}
}

func run(args []string) error {
	if len(args) == 0 {
		printUsage()
		return flag.ErrHelp
	}
	switch args[0] {
	case "validate":
		return validateCommand(args[1:])
	case "pack":
		return packCommand(args[1:])
	case "version", "--version":
		fmt.Println(version)
		return nil
	case "help", "-h", "--help":
		printUsage()
		return nil
	default:
		printUsage()
		return fmt.Errorf("unknown command %q", args[0])
	}
}

func validateCommand(args []string) error {
	flags := flag.NewFlagSet("validate", flag.ContinueOnError)
	flags.SetOutput(os.Stderr)
	if err := flags.Parse(args); err != nil {
		return err
	}
	if flags.NArg() != 1 {
		return errorsForUsage("validate requires exactly one directory or .splug path")
	}
	info, err := plugin.Validate(flags.Arg(0))
	if err != nil {
		return err
	}
	fmt.Printf(
		"valid: %s %s (API %s, %d files, %d bytes)\n",
		info.Manifest.ID,
		info.Manifest.Version,
		info.Manifest.APIVersion,
		info.Files,
		info.Bytes,
	)
	return nil
}

func packCommand(args []string) error {
	flags := flag.NewFlagSet("pack", flag.ContinueOnError)
	flags.SetOutput(os.Stderr)
	output := flags.String("output", "", "output .splug path")
	flags.StringVar(output, "o", "", "output .splug path")
	if err := flags.Parse(args); err != nil {
		return err
	}
	if flags.NArg() != 1 {
		return errorsForUsage("pack requires exactly one plugin source directory")
	}
	result, err := plugin.Pack(flags.Arg(0), *output)
	if err != nil {
		return err
	}
	fmt.Printf("packed: %s\nsha256: %s\nfiles: %d\n", result.Path, result.SHA256, result.Files)
	return nil
}

func errorsForUsage(message string) error {
	printUsage()
	return fmt.Errorf("%s", message)
}

func printUsage() {
	fmt.Fprintln(os.Stderr, `samp-plugin validates and packages SA-MP Android Lua plugins.

Usage:
  samp-plugin validate <directory|package.splug>
  samp-plugin pack [--output package.splug] <directory>
  samp-plugin version
  samp-plugin help`)
}
