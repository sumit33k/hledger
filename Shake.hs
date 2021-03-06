#!/usr/bin/env stack
{- stack exec
   --verbosity=info
   --package base-prelude
   --package directory
   --package extra
   --package safe
   --package shake
   --package time
   ghc
-}
--   --package pandoc
{-
One of two project scripts files (Makefile, Shake.hs).
This one provides a stronger programming language and more
platform independence than Make. It will build needed packages (above)
on first run and whenever the resolver in stack.yaml changes.
To minimise such startup delays, and reduce sensitivity to git checkout,
compiling is recommended; run the script in interpreted mode to do that.

It requires stack (https://haskell-lang.org/get-started) and
auto-installs the packages above. Also, some rules require:
- site/hakyll-std/hakyll-std
- runhaskell
- groff
- m4
- makeinfo
- git
- patch

Usage: see below. Also:

$ find hledger-lib hledger | entr ./Shake website    # rebuild web files on changes in these dirs

Shake wishes:
just one shake import
wildcards in phony rules
multiple individually accessible wildcards
not having to write :: Action ExitCode after a non-final cmd
-}

{-# LANGUAGE PackageImports, ScopedTypeVariables #-}

import                Prelude ()
import "base-prelude" BasePrelude
import "directory"    System.Directory as S (getDirectoryContents)
import "extra"        Data.List.Extra
import "safe"         Safe
import "shake"        Development.Shake
import "shake"        Development.Shake.FilePath
import "time"         Data.Time

usage = unlines
  ["Usage:"
  ,"./Shake.hs               # compile this script"
  ,"./Shake                  # show commands"
  ,"./Shake manuals          # generate the txt/man/info manuals"
  ,"./Shake website          # generate the html manuals and website"
--   ,"./Shake manpages         # generate nroff files for man"
--   ,"./Shake txtmanpages      # generate text man pages for embedding"
--   ,"./Shake infomanpages     # generate info files for info"
--   ,"./Shake webmanpages      # generate individual web man pages for hakyll"
--   ,"./Shake webmanall        # generate all-in-one web manual for hakyll"
  ,"./Shake site/doc/VER/.snapshot   # generate and save a versioned web site snapshot"
  ,"./Shake all              # generate everything"
  ,"./Shake clean            # clean generated files"
  ,"./Shake Clean            # clean harder"
  ,"./Shake --help           # show options, eg --color"
  ]

pandoc = "stack exec -- pandoc" -- pandoc from project's stackage snapshot
hakyllstd = "site/hakyll-std/hakyll-std"
makeinfo = "makeinfo"
-- nroff = "nroff"
groff = "groff"

main = do

  shakeArgs
    shakeOptions{
      shakeVerbosity=Loud
      -- ,shakeReport=[".shake.html"]
      } $ do

    want ["help"]

    phony "help" $ liftIO $ putStrLn usage

--     phony "compile" $ need ["Shake"]
--
--     "Shake" %> \out -> do
--       need [out <.> "hs"]
--       unit $ cmd "./Shake.hs"  -- running as stack script installs deps and compiles
--       putLoud "You can now run ./Shake instead of ./Shake.hs"

    phony "all" $ need ["manuals", "website"]

    -- manuals

    let
      manpageNames = [ -- in suggested reading order
         "hledger.1"
        ,"hledger-ui.1"
        ,"hledger-web.1"
        ,"hledger-api.1"
        ,"hledger_journal.5"
        ,"hledger_csv.5"
        ,"hledger_timeclock.5"
        ,"hledger_timedot.5"
        ]

      manualNames = map manpageNameToManualName manpageNames

      -- hledger.1 -> hledger, hledger_journal.5 -> hledger_journal
      manpageNameToManualName = dropNumericSuffix
        where
          dropNumericSuffix s = reverse $
            case reverse s of
              c : '.' : cs | isDigit c -> cs
              cs                       -> cs

      -- hledger -> hledger.1, hledger_journal -> hledger_journal.5
      manualNameToManpageName s
        | '_' `elem` s = s <.> "5"
        | otherwise    = s <.> "1"

      -- manuals m4 source; may include other source files (hledger/hledger.m4.md)
      m4manpages = [manualDir m </> m <.> "m4.md" | m <- manualNames]

      -- manuals rendered to nroff, ready for man (hledger/hledger.1)
      nroffmanpages = [manpageDir m </> m | m <- manpageNames]

      -- manuals rendered to text, ready for embedding (hledger/hledger.txt)
      txtmanpages = [manualDir m </> m <.> "txt" | m <- manualNames]

      -- manuals rendered to info, ready for info (hledger/hledger.info)
      infomanpages = [manualDir m </> m <.> "info" | m <- manualNames]

      -- manuals rendered to markdown, ready for web output by hakyll (site/hledger.md)
      webmanpages = ["site" </> manpageNameToUri m <.>"md" | m <- manpageNames]

      -- manuals rendered to markdown and combined, ready for web output by hakyll
      webmanall = "site/manual.md"

      -- hledger.1 -> hledger/doc, hledger_journal.5 -> hledger-lib/doc
      manpageDir m
        | '_' `elem` m = "hledger-lib"
        | otherwise    = dropExtension m

      -- hledger -> hledger, hledger_journal -> hledger-lib
      manualDir m
        | '_' `elem` m = "hledger-lib"
        | otherwise    = m

      -- hledger.1 -> hledger, hledger_journal.5 -> journal
      manpageNameToUri m | "hledger_" `isPrefixOf` m = dropExtension $ drop 8 m
                         | otherwise                 = dropExtension m

      -- hledger -> hledger.1, journal -> hledger_journal.5
      manpageUriToName u | "hledger" `isPrefixOf` u = u <.> "1"
                         | otherwise                = "hledger_" ++ u <.> "5"

    phony "manuals" $ do
      need $
        nroffmanpages
        ++ infomanpages
        ++ txtmanpages

    -- man pages

    -- use m4 and pandoc to process macros, filter content, and convert to nroff suitable for man output
    phony "manpages" $ need nroffmanpages

    nroffmanpages |%> \out -> do -- hledger/hledger.1
      let src = manpageNameToManualName out <.> "m4.md"
          lib = "doc/lib.m4"
          dir = takeDirectory out
          tmpl = "doc/manpage.nroff"
      -- assume all other m4 files in dir are included by this one XXX not true in hledger-lib
      deps <- liftIO $ filter (/= src) . filter (".m4.md" `isSuffixOf`) . map (dir </>) <$> S.getDirectoryContents dir
      need $ src : lib : tmpl : deps
      cmd Shell
        "m4 -P -DMAN -I" dir lib src "|"
        pandoc "-f markdown -s --template" tmpl
        "--lua-filter tools/pandoc-drop-html-blocks.lua"
        "--lua-filter tools/pandoc-drop-html-inlines.lua"
        "--lua-filter tools/pandoc-drop-links.lua"
        "-o" out

    -- render man page nroffs to fixed-width text for embedding in executables, with nroff
    phony "txtmanpages" $ need txtmanpages

    txtmanpages |%> \out -> do  -- hledger/hledger.txt
      let src = manualNameToManpageName $ dropExtension out
      need [src]
      cmd Shell groff "-t -e -mandoc -Tascii" src  "| col -bx >" out -- http://www.tldp.org/HOWTO/Man-Page/q10.html

    -- use m4 and pandoc to process macros, filter content, and convert to info, suitable for info viewing
    phony "infomanpages" $ need infomanpages

    infomanpages |%> \out -> do -- hledger/hledger.info
      let src = out -<.> "m4.md"
          lib = "doc/lib.m4"
          dir = takeDirectory out
      -- assume all other m4 files in dir are included by this one XXX not true in hledger-lib
      deps <- liftIO $ filter (/= src) . filter (".m4.md" `isSuffixOf`) . map (dir </>) <$> S.getDirectoryContents dir
      need $ src : lib : deps
      cmd Shell
        "m4 -P -I" dir lib src "|"
        pandoc "-f markdown"
        "--lua-filter tools/pandoc-drop-html-blocks.lua"
        "--lua-filter tools/pandoc-drop-html-inlines.lua"
        "--lua-filter tools/pandoc-drop-links.lua"
        "-t texinfo |"
        makeinfo "--force --no-split -o" out

    -- web site

    phony "website" $ do
      need $
        webmanpages ++
        [webmanall
        ,hakyllstd
        ]
      cmd Shell (Cwd "site") "hakyll-std/hakyll-std" "build"
    -- website also links to old manuals, which are generated manually
    -- with ./Shake websnapshot and committed
    -- TODO: when pandoc filters are missing, ./Shake website complains about them before building them 
    --   ./Shake.hs && ./Shake Clean && (cd site/hakyll-std; ./hakyll-std.hs) && ./Shake website

    -- use m4 and pandoc to process macros and filter content, leaving markdown suitable for web output
    phony "webmanpages" $ need webmanpages

    webmanpages |%> \out -> do -- site/hledger.md
      let manpage = manpageUriToName $ dropExtension $ takeFileName out -- hledger
          manual  = manpageNameToManualName manpage
          dir     = manpageDir manpage
          src     = dir </> manual <.> "m4.md"
          lib     = "doc/lib.m4"
          heading = let h = manual
                    in if "hledger_" `isPrefixOf` h
                       then drop 8 h ++ " format"
                       else h
      -- assume all other m4 files in dir are included by this one XXX not true in hledger-lib
      deps <- liftIO $ filter (/= src) . filter (".m4.md" `isSuffixOf`) . map (dir </>) <$> S.getDirectoryContents dir
      need $ src : lib : deps
      liftIO $ writeFile out $ "# " ++ heading ++ "\n\n"
      cmd Shell
        "m4 -P -DMAN -DWEB -I" dir lib src "|"
        pandoc "-f markdown -t markdown-fenced_divs --atx-headers"
        "--lua-filter tools/pandoc-demote-headers.lua"
        ">>" out

    -- adjust and combine man page mds for single-page web output, using pandoc
    phony "webmanall" $ need [ webmanall ]

    webmanall %> \out -> do
      need webmanpages
      liftIO $ writeFile webmanall "* toc\n\n" -- # Big Manual\n\n -- TOC style is better without main heading,
      forM_ webmanpages $ \f -> do -- site/hledger.md, site/journal.md
        cmd Shell ("printf '\\n\\n' >>") webmanall :: Action ExitCode
        cmd Shell "pandoc" f "-t markdown-fenced_divs --atx-headers"
          "--lua-filter tools/pandoc-drop-toc.lua"
          "--lua-filter tools/pandoc-demote-headers.lua"
          ">>" webmanall :: Action ExitCode

    -- adjust and combine recipe mds for single-page web output, using pandoc
    -- build the currently checked out web docs and save as a named snapshot
    "site/doc/*/.snapshot" %> \out -> do
      need [ webmanall ]
      let snapshot = takeDirectory out
      cmd Shell "mkdir -p" snapshot :: Action ExitCode
      forM_ webmanpages $ \f -> do -- site/hledger.md, site/journal.md
        cmd Shell "cp" f (snapshot </> takeFileName f) :: Action ExitCode
      cmd Shell "cp" "site/manual.md" snapshot :: Action ExitCode
      cmd Shell "cp -r site/images" snapshot :: Action ExitCode
      cmd Shell "touch" out -- :: Action ExitCode

    -- build standard hakyll script used for site rendering
    hakyllstd %> \out -> do
      let dir = takeDirectory out
      need [out <.> "hs", dir </> "TableOfContents.hs"] -- XXX hard-coded dep
      unit $ liftIO $
        cmd (Cwd dir) "./hakyll-std.hs"
        `catch` (\(e::IOException) -> putStr $ unlines $
          ["I could not run ./hakyll-std.hs in "++dir++" to install Hakyll."
          ,"If you see a hakyll-std build error after this, please do it manually:"
          ,"$ (cd site/hakyll-std; ./hakyll-std.hs)"
          ,"and try again."
          ])

    -- cleanup

    phony "clean" $ do
      putNormal "Cleaning generated files"
      removeFilesAfter "." webmanpages
      removeFilesAfter "." [webmanall]

    phony "Clean" $ do
      need ["clean"]
      putNormal "Cleaning all hakyll generated files"
      removeFilesAfter "site" ["_*"]
      putNormal "Cleaning executables"
      removeFilesAfter "." $ [ hakyllstd ]
      putNormal "Cleaning object files" -- also forces rebuild of executables
      removeFilesAfter "tools"  ["*.o","*.p_o","*.hi"]
      removeFilesAfter "site" ["*.o","*.p_o","*.hi"]
      putNormal "Cleaning shake build files"
      removeFilesAfter ".shake" ["//*"]
