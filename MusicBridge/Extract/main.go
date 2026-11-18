package main

import (
 "fmt"
 "os"
 "github.com/blacktop/ipsw/internal/commands/extract"
)

func main() {
 if len(os.Args)!=3 { panic("usage: kreshka-extract IPSW_URL OUTPUT") }
 files,err:=extract.Search(&extract.Config{
  URL:os.Args[1], Output:os.Args[2],
  Pattern:`^/private/var/staged_system_apps/Music[.]app/.*$`,
  DMGs:true, Ranged:true, RangedDMG:"fs", KernelDevice:"iPhone18,1",
 })
 if err!=nil { fmt.Fprintln(os.Stderr,err); os.Exit(1) }
 fmt.Printf("Extracted %d files\n",len(files))
 if len(files)<100 { os.Exit(2) }
}
