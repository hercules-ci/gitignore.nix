{ lib ? import <nixpkgs/lib> }:
let
  parse-ini = import ./parse-git-config.nix { inherit lib; };
  parse-gitignore = import ./rules.nix { inherit lib; };
in
rec {
  inherit (builtins) dirOf baseNameOf abort split hasAttr readFile readDir pathExists;
  inherit (lib.lists) filter length head tail concatMap take;
  inherit (lib.attrsets) filterAttrs mapAttrs attrNames;
  inherit (lib.strings) hasPrefix removePrefix splitString toLower;
  inherit (lib) strings flip any;
  inherit lib;
  inherit parse-ini;

  # TODO: 'filesystem.nix' 
  #         - readLines function with CRLF support
  # TODO: check assumption that a relative core.excludesFile is relative to HOME
  # TODO: write test for trailing slash (matches dir only)

  gitignoreFilter = basePath:
    gitignoreFilterWith { inherit basePath; };

  gitignoreFilterWith = { basePath, extraRules ? null, extraRulesWithContextDir ? [] }:
    assert extraRules == null || builtins.typeOf extraRules == "string";
    let
      extraRules2 = extraRulesWithContextDir ++ 
        lib.optional (extraRules != null) { contextDir = basePath; rules = extraRules; };
      patternsBelowP = findPatternsTree extraRules2 basePath;
      basePathStr = toString basePath;
    in
      path: type: let
        localDirPath = removePrefix basePathStr (toString (dirOf path));
        localDirPathElements = splitString "/" localDirPath;
        patternResult = parse-gitignore.runFilterPattern (getPatterns patternsBelowP localDirPathElements)."/patterns" path type;
        nonempty = any (nodeName: gitignoreFilter (basePath + "/${nodeName}") != false)
                       (attrNames (readDir path));
      in patternResult && (type == "directory" -> nonempty);

  getPatterns =
    patternTree: pathElems:
      if length pathElems == 0
      then patternTree
      else let hd = head pathElems; in
        if hd == "" || hd == "."
        then getPatterns patternTree (tail pathElems)
        else
          if hasAttr hd patternTree
          then getPatterns patternTree."${hd}" (tail pathElems)
          else
            # Files are not in the tree, so we return the
            # most patterns we could find here.
            patternTree;


  #####
  # Constructing a tree of patterns per non-ignored subdirectory, recursively
  #

  /* Given a dir, return a tree of patterns mirroring the directory structure,
     where the patterns on the nodes towards the leaves become more specific.

     It's a tree where the nodes are attribute sets and the keys are directory basenames.
     The patterns are mixed into the attrsets using the special key "/patterns".
     Leaves are simply {}
   */
  findPatternsTree = extraRules: dir:
    let
      listOfStartingPatterns = map ({contextDir, rules ? readFile file, file ? throw "gitignore.nix: A `file` or `rules` attribute is required in extraRulesWithContextDir items.", ...}: 
                                 parse-gitignore.gitignoreFilter rules contextDir
                              ) (findAncestryGitignores dir ++ extraRules);
      startingPatterns = builtins.foldl'
                           parse-gitignore.mergePattern
                           (defaultPatterns dir) # not the unit of merge but a set of defaults
                           listOfStartingPatterns;
    in
      findDescendantPatternsTree startingPatterns dir;

  # We do an eager-looking descent ourselves, in order to memoize the patterns.
  # In fact it is lazy, so some directories' patterns will not need to be
  # evaluated if not requested. This works out nicely when the user adds a
  # filter *before* the gitignore filter.
  #
  # This function assumes that the gitignore files that are specified *in*
  # dir, in the *ancestry* of dir or globally are already included in
  # currentPatterns.
  findDescendantPatternsTree = currentPatterns: dir:
    let nodes = readDir dir;
        dirs = filterAttrs (name: type:
                              type == nodeTypes.directory && 
                              (parse-gitignore.runFilterPattern currentPatterns (dir + "/${name}") type)
                           ) nodes;
    in mapAttrs (name: _t:
      let subdir = dir + "/${name}";
          ignore = subdir + "/.gitignore";
          newPatterns = map (file:
              parse-gitignore.mergePattern
                currentPatterns  # Performance: this is where you could potentially filter out patterns irrelevant to subdir
                (parse-gitignore.gitignoreFilter (readFile file) subdir)
            ) (guardFile ignore);
          subdirPatterns = headOr currentPatterns newPatterns;
      in 
        findDescendantPatternsTree subdirPatterns subdir
    ) dirs // { "/patterns" = currentPatterns; };
  defaultPatterns = root: parse-gitignore.gitignoreFilter ".git" root; # no trailing slash, because of worktree references


  #####
  # Finding the gitignore files in the current directory, towards the root and
  # in the user config.
  #
  findAncestryGitignores = path:
    let
      up = inspectDirAndUp path;
      inherit (up) localIgnores gitDir worktreeRoot;
      globalIgnores =
        if builtins?currentSystem
        # impure mode: we should account for the user's gitignores as their tooling
        #              can put impure files in the project
        then map (file: { contextDir = worktreeRoot; inherit file; }) maybeGlobalIgnoresFile
        # pure mode: we hope that all ignores are also in the project .gitignore
        else [];

      # TODO: can local config override global core.excludesFile?
      # localConfigItems = parse-ini.parseIniFile (gitDir + "/config");
    in
      globalIgnores ++ localIgnores;



  #####
  # Functions for getting "context" from directory ancestry, repo
  #

  /* path -> { localIgnores : list {contextDir, file}
             , gitDir : path }
    
     Precondition: dir exists and is a directory


   */
  inspectDirAndUp = dirPath: let
      go = p: acc:
        let
          parentDir = dirOf p;
          dirInfo = inspectDir p;
          isHighest = dirInfo.isWorkTreeRoot || p == /. || p == "/";
          dirs = [dirInfo] ++ acc;

          getIgnores = di: if di.hasGitignore
            then [{ contextDir = di.dirPath; file = di.dirPath + "/.gitignore"; }]
            else [];

        in
          if isHighest || isForbiddenDir (toString parentDir)
          then
            {
              localIgnores = concatMap getIgnores dirs;
              worktreeRoot = p;
              inherit (dirInfo) gitDir;
            }
          else
            go parentDir dirs
      ;
    in go dirPath [];

  # isForbiddenDir: string -> bool
  #
  # Some directories should never be traversed when looking for .git
  #  - for performance
  #  - to help lorri and possibly other tools that monitor which paths are read
  #    during evaluation
  isForbiddenDir = p:
    p == builtins.storeDir || p == "/";

  inspectDir = dirPath:
    let
      d = readDir dirPath;
      dotGitType = d.".git" or null;
      isWorkTreeRoot = pathExists (dirPath + "/.git");
      gitDir = if dotGitType == nodeTypes.directory then dirPath + "/.git"
               else if dotGitType == nodeTypes.regular then readDotGitFile (dirPath + "/.git")
               else if dotGitType == nodeTypes.symlink then throw "gitignore.nix: ${toString dirPath}/.git is a symlink. This is not supported (yet?)."
               else if dotGitType == null then null
               else throw "gitignore.nix: ${toString dirPath}/.git is of unknown node type ${dotGitType}";

      # directory should probably be ignored here, but to figure out the node type, we
      # currently don't have a builtin to do it directly and readDir is expensive,
      # particularly for a tool like lorri.
      hasGitignore = pathExists (dirPath + "/.gitignore");
    in { inherit isWorkTreeRoot hasGitignore gitDir dirPath; };
  
  /* .git file path -> GIT_DIR

     Used for establishing $GIT_DIR when the worktree is an external worktree,
     when .git is a file.
   */
  readDotGitFile = filepath:
    let contents = readFile filepath;
        lines = lib.strings.splitString "\n" contents;
        gitdirLines = map (strings.removePrefix "gitdir: ") (filter (lib.strings.hasPrefix "gitdir: ") lines);
        errNoGitDirLine = abort ("Could not find a gitdir line in " + filepath);
    in /. + headOr errNoGitDirLine gitdirLines
  ;

  /* default -> list -> head or default
   */
  headOr = default: l:
    if length l == 0 then default else head l;



  #####
  # Finding git config
  #

  home = if lib.inPureEvalMode or false then _: /nonexistent else import ./home.nix;

  maybeXdgGitConfigFile = 
    for
      (guardNonEmptyString (builtins.getEnv "XDG_CONFIG_HOME"))
      (xdgConfigHome:
        guardFile (/. + xdgConfigHome + "/git/config")
      );
  maybeGlobalConfig = take 1 (guardFile (home /.gitconfig)
                           ++ maybeXdgGitConfigFile
                           ++ guardFile (home /.config/git/config));

  globalConfigItems = for maybeGlobalConfig (globalConfigFile:
    parse-ini.parseIniFile globalConfigFile
  );
  globalConfiguredExcludesFile = take 1 (
    for
      globalConfigItems
      ({section, key, value}:
        for
          (guard (toLower section == "core" && toLower key == "excludesfile"))
          (_:
            resolveFile (home /.) value
          )
      )
    );
  xdgExcludesFile = for
    (guardNonEmptyString (builtins.getEnv "XDG_CONFIG_HOME"))
    (xdgConfigHome:
      guardFile (/. + xdgConfigHome + "/git/ignore")
    );
  maybeGlobalIgnoresFile = take 1
                            ( globalConfiguredExcludesFile
                           ++ xdgExcludesFile
                           ++ guardFile (home /.config/git/ignore));

  /* Given baseDir, which generalizes the idea of working directory,
     resolve a file path relative to that directory.

     It will return at most 1 path; 0 if no such file could be found.
     Absolute paths and home-relative (~) paths ignore the baseDir, unless
     the
   */
  resolveFile = baseDir: path: take 1
    (  if hasPrefix "/" path then guardFile (/. + path) else 
         (if hasPrefix "~" path then guardFile (home /. + removePrefix "~" path) else [])
         ++ guardFile (baseDir + "/" + path)
    )
  ;


  #####
  # List as a search and backtracking tool
  #

  nullableToList = x: if x == null then [] else [x];
  for = l: f: concatMap f l;
  guard = b: if b then [{}] else [];

  /*
     Check whether a path exists; if it does, return it as a singleton list.

     Currently it checks whether a path exists, but we'd like to check the
     node type, so we don't try to readFile for example a directory if we don't
     have to.
     It can be done with readDir but this causes lorri to watch everything,
     which is really bad when reading for example ~/.gitconfig.
   */
  # TODO: get something like builtins.pathType or builtins.stat into Nix
  guardFile = p: if pathExists p then [p] else [];
  guardNonEmptyString = s: if s == "" then [s] else [];
  guardNonNull = a: if a != null then a else [];



  #####
  # Working with readDir output
  #

  nodeTypes.directory = "directory";
  nodeTypes.regular = "regular";
  nodeTypes.symlink = "symlink";

  # TODO: Assumes that it's a file when it's a symlink
  nodeTypes.isFile = p: p == nodeTypes.regular || p == nodeTypes.symlink;



  #####
  # Generic file system functions
  #

  /* path -> nullable nodeType
   * Without throwing (unrecoverable) errors
   */
  safeGetNodeType = path:
    if toString path == "/" then nodeTypes.directory
    else if pathExists path
    then let parentDir = readDir (dirOf path);
         in parentDir."${baseNameOf path}" or null
    else null;


}
