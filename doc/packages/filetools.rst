Package: src/packages/filetools.fdoc


==========
File Tools
==========

===================== ====================================
key                   file                                 
===================== ====================================
flx_ls.flx            $PWD/src/tools/flx_ls.flx            
flx_cp_tool.flx       $PWD/src/tools/flx_cp.flx            
flx_grep.flx          $PWD/src/tools/flx_grep.flx          
flx_replace.flx       $PWD/src/tools/flx_replace.flx       
flx_batch_replace.flx $PWD/src/tools/flx_batch_replace.flx 
flx_renumber.flx      $PWD/src/tools/flx_renumber.flx      
flx_cp.flx            share/lib/std/felix/flx_cp.flx       
===================== ====================================



File System Tools.
==================

The tools perform basic tasks the same way on all platforms.
Our tools use RE2 (Perl) regular expressions for wildcarding instead
of globs. All tools treat the file system as flat: directories
don't exist. Structured filenames do. Tools creating files
always auto-create directories for this reason.

Most of the tools are stubs wrapping core library
functionality.

Note: the regular expressions must match completely.

File list  :code:`flx_ls`.
--------------------------

List all files in a given master directory matching the
specified pattern. The resulting list is relative
to the master directory.

Note: regular expressions must match completely!


.. code-block:: felix

  //[flx_ls.flx]
  fun dbg(s:string):string={ println s; return s; }
  //println$ System::args ();
  //println$ "argc=" + str System::argc;
  
  var dir = 
    if System::argc < 2 then Directory::getcwd()
    else System::argv 1
    endif
  ;
  
  var regex = 
    if System::argc < 3 then ".*"
    else System::argv 2
    endif
  ;
  
  //println$ "Dir=" dir;
  //println$ "Files in dir " + dir + "=";
  iter (proc (s:string) { println s; }) (FileSystem::regfilesin (dir, regex));


File copy  :code:`flx_cp`.
--------------------------

This tool copies files using regular expressions with
a replacement pattern. The tool is safe in that it guarrantees
the copy is one-to-one and the target files do not overlap
the source files. If this condition isn't met the copy fails
as a whole.

The copy is done like  :code:`flx_ls` scanning for structured
filenames in a given master directory matching a given
pattern. The destination replacement pattern is must include
any required prefix (the master directory is only used for
searching as an optimisation). The encoding  :code:`\n` where
n is a digit from 0 to 9 represents a subgroup of the match.

Note: regular expressions must match completely!


.. code-block:: felix

  //[flx_cp_tool.flx]
  include "std/felix/flx_cp";
  
  fun dbg(s:string):string={ println s; return s; }
  //println$ System::args ();
  //println$ "argc=" + str System::argc;
  
  var dir = "";
  var regex = "";
  var target = "";
  var live = true;
  var verbose = false;
  
  for var i in 1 upto System::argc do
    var arg = System::argv i;
    if arg == "--test" do live = false; 
    elif arg == "-v" or arg == "--verbose" do verbose = true;
    elif arg.[0] == char "-" do
      println$ "Unknown option '" + arg+"'"; 
      System::exit(1);
    elif dir == "" do dir = arg;
    elif regex == "" do regex = arg;
    elif target == "" do target = arg;
    done
  done
  
  if dir == "" do println$ "Missing directory name (arg1)"; System::exit(1);
  elif regex == "" do println$ "Missing regex (arg2)"; System::exit(1);
  elif target == "" do println$ "Missing target (arg3)"; System::exit(1);
  done
  
  if verbose do println$ "#Dir='" + dir + "', pattern='"+regex+"', dst='"+target+"'"; done
  
  var re = Re2::RE2 regex;
  CopyFiles::copyfiles (dir, re, target, live, verbose);
  System::exit(0);


.. index:: CopyFiles(class)
.. index:: processfiles(proc)
.. index:: copyfiles(proc)
.. index:: copyfiles(proc)
.. code-block:: felix

  //[flx_cp.flx]
  class CopyFiles {
    proc processfiles 
      (var process: string * string -> bool) 
      (basedir:string, re:RE2, tpat:string, live:bool, verbose:bool)
    {
       var ds = StrDict::strdict[string] ();
       var sd = StrDict::strdict[string] ();
       var dirs = StrDict::strdict[bool] ();
       var n = re.NumberOfCapturingGroups;
       var v = varray[StringPiece]$ (n+1).size, StringPiece "";
  //println$ "flx_cp:CopyFiles:processfiles regexp= " + re.pattern;
       // Process a single filename and add it to the pending copy queue
       proc addfile(f:string)
       {
          if Re2::Match(re, StringPiece f, 0, ANCHOR_BOTH, v.stl_begin, v.len.int)
          do
            var src = Filename::join (basedir, f);
            var replacements = Empty[string * string];
            for var k in 0 upto n do
              replacements = Cons (("${" + str k + "}",v.k.string), replacements);
            done
            dst := search_and_replace replacements tpat;
  
            //println$ "Copy " + src + " -> " + dst;
            sd.add src dst;
  
            if ds.haskey dst do
              eprintln$ "Duplicate target " + dst;
              System::exit(1);
            done
            ds.add dst src;
            iter
              (proc (x:string) { dirs.add x true; })
              (Filename::directories dst)
            ;
          done
       }
  
       // Recursively collect files within dir to be copied. dir is relative to basedir.
       proc rfi(dir: string)
       {
         if dir != "." and dir != ".." do
         match Directory::filesin(Filename::join (basedir,dir)) with
         | #None  => ;
         | Some files =>
           List::iter
             (proc (f:string)
             { if f != "." and f != ".." do
                 var d = Filename::join (dir,f);
                 val t = FileStat::filetype (Filename::join (basedir,d));
                 match t with
                   | #REGULAR => addfile d;
                   | #DIRECTORY => rfi d;
                   | _ => ;
                 endmatch;
               done
             }
             )
             files
           ;
         endmatch;
         done
       }
       rfi ("");
  
       // Check that no source file is clobbered
       match src, dst in sd.iterator do
         if sd.haskey dst do
           eprintln$ "Target clobbers src: " + dst;
           System::exit(1);
         done
       done
  
       // Create target directories
       match dir, _ in dirs.iterator do
         if verbose do println$ "mkdir " + dir; done
         if live do
           err:=Directory::mkdir(dir);
           if err !=0 do
             if errno != EEXIST do
               eprintln$ "Mkdir, err=" + strerror() + " .. ignoring";
             done
           done
         done
       done
  
       // And finally, do the actual copying
       match src, dst in sd.iterator do
         if verbose do print$ "cp " + src + "  " + dst; done
         if live do
           if process(src, dst) do
             if verbose do println " #done"; done
           else
             eprintln "COPY FAILED";
             System::exit 1;
           done
         else
           if verbose do println$ "  #proposed"; done
         done
       done
    }
  
    proc copyfiles(basedir:string, re:RE2, tpat:string, live:bool, verbose:bool) =>
      processfiles (FileSystem::filecopy) (basedir, re, tpat, live, verbose)
    ;
  
    proc copyfiles(basedir:string, re:string, tpat:string, live:bool, verbose:bool) =>
      copyfiles(basedir, RE2 re, tpat, live, verbose)
    ;
  }


Searching for strings  :code:`flx_grep`.
----------------------------------------

This tool works like grep except the files being searched
use a master directory and regular expression for selection.
Any line in any of those files matching the given regexp
completely are listed.


.. code-block:: felix

  //[flx_grep.flx]
  var dir = 
    if System::argc < 2 then Directory::getcwd()
    else System::argv 1
    endif
  ;
  
  var fregex = 
    if System::argc < 3 then ".*"
    else System::argv 2
    endif
  ;
  
  var lregex = 
    if System::argc < 4 then ".*"
    else System::argv 3
    endif
  ;
  
  var grexp = RE2 lregex;
  
  //println$ "Dir=" dir;
  //println$ "Files in dir " + dir + "=";
  for file in FileSystem::regfilesin (dir, fregex) do
  //  println$ file;
    var lines = load (Filename::join dir file);
    var count = 0;
    for line in split (lines,char "\n") do
      ++count;
      if line \in grexp do
        println$ file+":"+str count+": " line;
      done
    done
  done
  
  


Replace substrings in a file.
-----------------------------

This tool replaces patterns found in a single
file with another pattern and outputs the result
to standard output.


.. code-block:: felix

  //[flx_replace.flx]
  var filename = System::argv 1;
  var re = System::argv 2;
  var r = System::argv 3;
  
  if System::argc != 4 do
    println$ "Usage: flx_replace filename regexp replacement";
    println$ "  replacement may contain \\1 \\2 etc for matching subgroups";
    System::exit 1;
  done
  
  
  var x = load filename;
  var cre = RE2 re;
  var result = search_and_replace (x, 0uz, cre, r);
  print result;
  


Batch Replace
-------------

This program combines  :code:`flx_cp` and  :code:`flx_replace` to perform
a wildcarded safe copy of a set of files from one location
to another with renaming, and also replaces any lines in
any of the files matching some pattern with another string
specified by a replacement.

.. code-block:: felix

  //[flx_batch_replace.flx]
  include "std/felix/flx_cp";
  
  fun dbg(s:string):string={ println s; return s; }
  //println$ System::args ();
  //println$ "argc=" + str System::argc;
  
  var dir = "";
  var regex = "";
  var target = "";
  var search = "";
  var replace = "";
  var live = true;
  var verbose = false;
  
  for var i in 1 upto System::argc do
    var arg = System::argv i;
    if arg == "--test" do live = false; 
    elif arg == "-v" or arg == "--verbose" do verbose = true;
    elif arg.[0] == char "-" do
      println$ "Unknown option '" + arg+"'"; 
      System::exit(1);
    elif dir == "" do dir = arg;
    elif regex == "" do regex = arg;
    elif target == "" do target = arg;
    elif search == "" do search = arg;
    elif replace == "" do replace = arg;
    done
  done
  
  if dir == "" do println$ "Missing directory name (arg1)"; System::exit(1);
  elif regex == "" do println$ "Missing regex (arg2)"; System::exit(1);
  elif target == "" do println$ "Missing target (arg3)"; System::exit(1);
  elif search == "" do println$ "Missing search regex (arg4)"; System::exit(1);
  elif replace == "" do println$ "Missing replace spec (arg5)"; System::exit(1);
  done
  
  if verbose do println$ "#Dir='" + dir + "', pattern='"+regex+"', dst='"+target+"'"; done
  
  var searchre = RE2 search;
  gen sandr (src: string, dst:string) = 
  {
    var text = load src;
    var result = search_and_replace (text, 0uz, searchre, replace); 
    save (dst, result);
    return true;
  }
  
  var filere = Re2::RE2 regex;
  CopyFiles::processfiles sandr (dir, filere, target, live, verbose);
  System::exit(0);


Renumbering.
------------

This tool analyses a single directory looking for files whose
basename matches a pattern containing a number in a fixed
position.

It then renumbers all the files with a number greater or equal
to a specified value, adding or subtracting a certain amount
to make space in the sequence or fill a gap in it.

It was designed for document renumbering, especially Felix
tutorial documents, since the Felix webserver automatically
calculates Next and Prev links when it asked to display
an  :code:`fdoc` file with a numerical suffix of two digits.
However it can be used on any sequenced file set.


.. code-block:: felix

  //[flx_renumber.flx]
  // File renumbering
  
  if System::argc < 4 do
    println "Usage: rentut dir regexp first dst";
    println "For tutorial try:";
    println r"  dir = 'src/web'";
    println r"  re = 'tut_(\d*)\\.fdoc'";
    System::exit(1);
  done
  
  s_dir := System::argv 1;
  s_re := System::argv 2;
  s_first := System::argv 3;
  s_moveto  := System::argv 4;
  
  first := size s_first;
  moveto := size s_moveto;
  re := RE2(s_re);
  if first == moveto do
    println$ "src = dst, not moving anything";
    System::exit 0;
  done
  
  println$ "Renumber files in " + s_dir+ " matching "+"'"+s_re+"'"+" from " + str first + " to " + str moveto;
  
  docs := FileSystem::regfilesin(s_dir, re);
  var files = varray docs;
  
  // direction: if first < moveto, we're moving up, so we have to start at the end and work down.
  // if first > moveto, we're moving down, so we have to start at the start and work up.
  comparator := if first < moveto then \gt of (string * string) else \lt of (string * string) endif;
  
  sort comparator of (string * string) files;
  println$ "Files = " + str files;
  var groups : array[StringPiece,2];
  
  iter 
    (proc(var f:string){
      println f;
      res := Match(re, StringPiece f,0,ANCHOR_BOTH,C_hack::cast[+StringPiece] (&groups),2);
      if res do
        //println$ "Group 1 = " + str (groups.1);
        n := size (str (groups.1));
        if n >= first do
          m := n + moveto - first;
          s := f"%02d" m.int;
          soffset := groups.1.data - (&f).stl_begin;
          var newf = f;
          replace(&newf,soffset.size,2uz,s);
          res2 := FileSystem::rename_file(
            Filename::join (s_dir,f),
            Filename::join (s_dir,newf)
          ); 
          if res2 != 0 do
            println$ "Rename " + f + " -> " + newf + " failed";
          else
            println$ f + " -> " + newf;
          done
        else
          // println$ str n + " Unchanged";
        done
      else
        println "NO match";
      done
    }) 
  files;
  


