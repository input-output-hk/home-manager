{ config, lib, pkgs, ... }:

with lib;

let

  cfg = config.programs.neovim;

  fileType = (import ../lib/file-type.nix {
    inherit (config.home) homeDirectory;
    inherit lib pkgs;
  }).fileType;

  jsonFormat = pkgs.formats.json { };

  extraPython3PackageType = mkOptionType {
    name = "extra-python3-packages";
    description = "python3 packages in python.withPackages format";
    check = with types;
      (x: if isFunction x then isList (x pkgs.python3Packages) else false);
    merge = mergeOneOption;
  };

  # Currently, upstream Neovim is pinned on Lua 5.1 for LuaJIT support.
  # This will need to be updated if Neovim ever migrates to a newer
  # version of Lua.
  extraLua51PackageType = mkOptionType {
    name = "extra-lua51-packages";
    description = "lua5.1 packages in lua5_1.withPackages format";
    check = with types;
      (x: if isFunction x then isList (x pkgs.lua51Packages) else false);
    merge = mergeOneOption;
  };

  pluginWithConfigType = types.submodule {
    options = {
      config = mkOption {
        type = types.nullOr types.lines;
        description =
          "Script to configure this plugin. The scripting language should match type.";
        default = null;
      };

      type = mkOption {
        type =
          types.either (types.enum [ "lua" "viml" "teal" "fennel" ]) types.str;
        description =
          "Language used in config. Configurations are aggregated per-language.";
        default = "viml";
      };

      optional = mkEnableOption "optional" // {
        description = "Don't load by default (load with :packadd)";
      };

      plugin = mkOption {
        type = types.package;
        description = "vim plugin";
      };

      runtime = mkOption {
        default = { };
        # passing actual "${xdg.configHome}/nvim" as basePath was a bit tricky
        # due to how fileType.target is implemented
        type = fileType "<varname>xdg.configHome/nvim</varname>" "nvim";
        example = literalExpression ''
          { "ftplugin/c.vim".text = "setlocal omnifunc=v:lua.vim.lsp.omnifunc"; }
        '';
        description = lib.mdDoc ''
          Set of files that have to be linked in nvim config folder.
        '';
      };
    };
  };

  allPlugins = cfg.plugins ++ optional cfg.coc.enable {
    type = "viml";
    plugin = cfg.coc.package;
    config = cfg.coc.pluginConfig;
    optional = false;
  };

  extraMakeWrapperArgs = lib.optionalString (cfg.extraPackages != [ ])
    ''--suffix PATH : "${lib.makeBinPath cfg.extraPackages}"'';
  extraMakeWrapperLuaCArgs = lib.optionalString (cfg.extraLuaPackages != [ ]) ''
    --suffix LUA_CPATH ";" "${
      lib.concatMapStringsSep ";" pkgs.lua51Packages.getLuaCPath
      cfg.extraLuaPackages
    }"'';
  extraMakeWrapperLuaArgs = lib.optionalString (cfg.extraLuaPackages != [ ]) ''
    --suffix LUA_PATH ";" "${
      lib.concatMapStringsSep ";" pkgs.lua51Packages.getLuaPath
      cfg.extraLuaPackages
    }"'';

in {
  imports = [
    (mkRemovedOptionModule [ "programs" "neovim" "withPython" ]
      "Python2 support has been removed from neovim.")
    (mkRemovedOptionModule [ "programs" "neovim" "extraPythonPackages" ]
      "Python2 support has been removed from neovim.")
    (mkRemovedOptionModule [ "programs" "neovim" "configure" ] ''
      programs.neovim.configure is deprecated.
            Other programs.neovim options can override its settings or ignore them.
            Please use the other options at your disposal:
              configure.packages.*.opt  -> programs.neovim.plugins = [ { plugin = ...; optional = true; }]
              configure.packages.*.start  -> programs.neovim.plugins = [ { plugin = ...; }]
              configure.customRC -> programs.neovim.extraConfig
    '')
  ];

  options = {
    programs.neovim = {
      enable = mkEnableOption "Neovim";

      viAlias = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Symlink <command>vi</command> to <command>nvim</command> binary.
        '';
      };

      vimAlias = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Symlink <command>vim</command> to <command>nvim</command> binary.
        '';
      };

      vimdiffAlias = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Alias <command>vimdiff</command> to <command>nvim -d</command>.
        '';
      };

      withNodeJs = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Enable node provider. Set to <literal>true</literal> to
          use Node plugins.
        '';
      };

      withRuby = mkOption {
        type = types.nullOr types.bool;
        default = true;
        description = ''
          Enable ruby provider.
        '';
      };

      withPython3 = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Enable Python 3 provider. Set to <literal>true</literal> to
          use Python 3 plugins.
        '';
      };

      extraPython3Packages = mkOption {
        type = with types; either extraPython3PackageType (listOf package);
        default = (_: [ ]);
        defaultText = literalExpression "ps: [ ]";
        example = literalExpression "(ps: with ps; [ python-language-server ])";
        description = ''
          A function in python.withPackages format, which returns a
          list of Python 3 packages required for your plugins to work.
        '';
      };

      extraLuaPackages = mkOption {
        type = with types; either extraLua51PackageType (listOf package);
        default = [ ];
        defaultText = literalExpression "[ ]";
        example = literalExpression "(ps: with ps; [ luautf8 ])";
        description = ''
          A function in lua5_1.withPackages format, which returns a
          list of Lua packages required for your plugins to work.
        '';
      };

      generatedConfigViml = mkOption {
        type = types.lines;
        visible = true;
        readOnly = true;
        description = ''
          Generated vimscript config.
        '';
      };

      generatedConfigs = mkOption {
        type = types.attrsOf types.lines;
        visible = true;
        readOnly = true;
        example = literalExpression ''
          {
            viml = '''
              " Generated by home-manager
              map <leader> ,
            ''';

            lua = '''
              -- Generated by home-manager
              vim.opt.background = "dark"
            ''';
          }'';
        description = ''
          Generated configurations with as key their language (set via type).
        '';
      };

      package = mkOption {
        type = types.package;
        default = pkgs.neovim-unwrapped;
        defaultText = literalExpression "pkgs.neovim-unwrapped";
        description = "The package to use for the neovim binary.";
      };

      finalPackage = mkOption {
        type = types.package;
        visible = false;
        readOnly = true;
        description = "Resulting customized neovim package.";
      };

      extraConfig = mkOption {
        type = types.lines;
        default = "";
        example = ''
          set nobackup
        '';
        description = ''
          Custom vimrc lines.
        '';
      };

      extraPackages = mkOption {
        type = with types; listOf package;
        default = [ ];
        example = literalExpression "[ pkgs.shfmt ]";
        description = "Extra packages available to nvim.";
      };

      plugins = mkOption {
        type = with types; listOf (either package pluginWithConfigType);
        default = [ ];
        example = literalExpression ''
          with pkgs.vimPlugins; [
            yankring
            vim-nix
            { plugin = vim-startify;
              config = "let g:startify_change_to_vcs_root = 0";
            }
          ]
        '';
        description = ''
          List of vim plugins to install optionally associated with
          configuration to be placed in init.vim.

          </para><para>

          This option is mutually exclusive with <varname>configure</varname>.
        '';
      };

      coc = {
        enable = mkEnableOption "Coc";

        package = mkOption {
          type = types.package;
          default = pkgs.vimPlugins.coc-nvim;
          defaultText = literalExpression "pkgs.vimPlugins.coc-nvim";
          description = "The package to use for the CoC plugin.";
        };

        settings = mkOption {
          type = jsonFormat.type;
          default = { };
          example = literalExpression ''
            {
              "suggest.noselect" = true;
              "suggest.enablePreview" = true;
              "suggest.enablePreselect" = false;
              "suggest.disableKind" = true;
              languageserver = {
                haskell = {
                  command = "haskell-language-server-wrapper";
                  args = [ "--lsp" ];
                  rootPatterns = [
                    "*.cabal"
                    "stack.yaml"
                    "cabal.project"
                    "package.yaml"
                    "hie.yaml"
                  ];
                  filetypes = [ "haskell" "lhaskell" ];
                };
              };
            };
          '';
          description = ''
            Extra configuration lines to add to
            <filename>$XDG_CONFIG_HOME/nvim/coc-settings.json</filename>
            See
            <link xlink:href="https://github.com/neoclide/coc.nvim/wiki/Using-the-configuration-file" />
            for options.
          '';
        };

        pluginConfig = mkOption {
          type = types.lines;
          default = "";
          description = "Script to configure CoC. Must be viml.";
        };
      };
    };
  };

  config = let
    defaultPlugin = {
      type = "viml";
      plugin = null;
      config = null;
      optional = false;
      runtime = { };
    };

    # transform all plugins into a standardized attrset
    pluginsNormalized =
      map (x: defaultPlugin // (if (x ? plugin) then x else { plugin = x; }))
      allPlugins;

    suppressNotVimlConfig = p:
      if p.type != "viml" then p // { config = null; } else p;

    neovimConfig = pkgs.neovimUtils.makeNeovimConfig {
      inherit (cfg) extraPython3Packages withPython3 withRuby viAlias vimAlias;
      withNodeJs = cfg.withNodeJs || cfg.coc.enable;
      plugins = map suppressNotVimlConfig pluginsNormalized;
      customRC = cfg.extraConfig;
    };

  in mkIf cfg.enable {

    programs.neovim.generatedConfigViml = neovimConfig.neovimRcContent;

    programs.neovim.generatedConfigs = let
      grouped = lib.lists.groupBy (x: x.type) pluginsNormalized;
      concatConfigs = lib.concatMapStrings (p: p.config);
      configsOnly = lib.foldl
        (acc: p: if p.config != null then acc ++ [ (p.config) ] else acc) [ ];
    in mapAttrs (name: vals: lib.concatStringsSep "\n" (configsOnly vals))
    grouped;

    home.packages = [ cfg.finalPackage ];

    xdg.configFile =
      let hasLuaConfig = hasAttr "lua" config.programs.neovim.generatedConfigs;
      in mkMerge (
        # writes runtime
        (map (x: x.runtime) pluginsNormalized) ++ [{
          "nvim/init.vim" = mkIf (neovimConfig.neovimRcContent != "") {
            text = neovimConfig.neovimRcContent;
          };
          "nvim/init.lua" = let
            luaRcContent =
              lib.optionalString (neovimConfig.neovimRcContent != "")
              "vim.cmd.source ${config.xdg.configHome}/nvim/init.vim"
              + lib.optionalString hasLuaConfig
              config.programs.neovim.generatedConfigs.lua;
          in mkIf (luaRcContent != "") { text = luaRcContent; };

          "nvim/coc-settings.json" = mkIf cfg.coc.enable {
            source = jsonFormat.generate "coc-settings.json" cfg.coc.settings;
          };
        }]);

    programs.neovim.finalPackage = pkgs.wrapNeovimUnstable cfg.package
      (neovimConfig // {
        wrapperArgs = (lib.escapeShellArgs neovimConfig.wrapperArgs) + " "
          + extraMakeWrapperArgs + " " + extraMakeWrapperLuaCArgs + " "
          + extraMakeWrapperLuaArgs;
        wrapRc = false;
      });

    programs.bash.shellAliases = mkIf cfg.vimdiffAlias { vimdiff = "nvim -d"; };
    programs.fish.shellAliases = mkIf cfg.vimdiffAlias { vimdiff = "nvim -d"; };
    programs.zsh.shellAliases = mkIf cfg.vimdiffAlias { vimdiff = "nvim -d"; };
  };
}
