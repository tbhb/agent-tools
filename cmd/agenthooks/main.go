// SPDX-License-Identifier: Apache-2.0
// Copyright Tony Burns

// Command agenthooks provides one of the shared agent tools for tbhb
// repositories.
package main

import (
	"os"

	"github.com/spf13/cobra"

	"github.com/tbhb/repotools/internal/buildmeta"
)

func main() {
	rootCmd := newRootCmd()
	if err := rootCmd.Execute(); err != nil {
		os.Exit(1)
	}
}

func newRootCmd() *cobra.Command {
	root := &cobra.Command{
		Use:           "agenthooks",
		Short:         "Shared agent tool for tbhb repositories",
		Version:       buildmeta.Version,
		SilenceUsage:  true,
		SilenceErrors: true,
	}

	root.AddCommand(newVersionCmd())
	return root
}

func newVersionCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "version",
		Short: "Print version, commit, and build date",
		Args:  cobra.NoArgs,
		Run: func(cmd *cobra.Command, _ []string) {
			info := buildmeta.Get()
			cmd.Printf("agenthooks %s\ncommit: %s\ndate:   %s\n", info.Version, info.Commit, info.Date)
		},
	}
}
