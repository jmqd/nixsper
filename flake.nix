{
  description = "Nixsper environment";

  inputs = { nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable"; };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      # Configure nixpkgs to allow unfree software
      pkgs = import nixpkgs {
        inherit system;
        config = {
          allowUnfree = true;
          cudaSupport = true;
        };
      };

      # We use a pre-built wheel for ctranslate2 to avoid the heavy compilation from source
      # (especially the C++ backend with CUDA support).
      # The wheel comes with the C++ library bundled.
      python3WithCuda = pkgs.python3.override {
        packageOverrides = self: super: {
          ctranslate2 = super.buildPythonPackage {
            pname = "ctranslate2";
            version = "4.6.2";
            format = "wheel";

            src = pkgs.fetchurl {
              url =
                "https://files.pythonhosted.org/packages/5b/24/ae556f98710eb83297a3807f3b7504af5b8c603d51e38310d3af804ff86a/ctranslate2-4.6.2-cp313-cp313-manylinux2014_x86_64.manylinux_2_17_x86_64.whl";
              sha256 =
                "ac1207e1aef08bf3679f33848b96f23a4d3ea078296cee473cce6a148cd8e145";
            };

            nativeBuildInputs = [ pkgs.autoPatchelfHook ];

            buildInputs = [
              pkgs.cudaPackages.cudatoolkit
              pkgs.cudaPackages.cudnn
              pkgs.stdenv.cc.cc.lib
            ];

            propagatedBuildInputs = [ super.numpy ];
          };
        };
      };

      nixsperPackage = python3WithCuda.pkgs.buildPythonApplication {
        pname = "nixsper";
        version = "0.1.0";
        src = ./.;
        format = "other"; # We don't have a setup.py

        propagatedBuildInputs = with python3WithCuda.pkgs; [
          faster-whisper
          sounddevice
          numpy
        ];

        buildInputs = with pkgs; [
          xdotool
          portaudio
          cudatoolkit
          cudaPackages.cudnn
        ];

        # Wrap the binary with the necessary paths
        makeWrapperArgs = [
          "--prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.xdotool ]}"
          # We need to ensure the CUDA libraries are found.
          # /run/opengl-driver/lib is needed for the system NVIDIA driver libs (libcuda.so)
          "--prefix LD_LIBRARY_PATH : ${
            pkgs.lib.makeLibraryPath [
              pkgs.cudatoolkit
              pkgs.cudaPackages.cudnn
            ]
          }:/run/opengl-driver/lib"
        ];

        installPhase = ''
          runHook preInstall
          install -Dm755 daemon.py $out/bin/nixsper-daemon
          runHook postInstall
        '';
      };

    in {
      packages.${system} = {
        default = nixsperPackage;
        nixsper = nixsperPackage;
      };

      nixosModules.default = { config, lib, pkgs, ... }: {
        options.services.nixsper = {
          enable = lib.mkEnableOption "Nixsper voice typing daemon";
          package = lib.mkOption {
            type = lib.types.package;
            default = self.packages.${pkgs.system}.default;
            description = "The nixsper daemon that can transcribe audio.";
          };
        };

        config = lib.mkIf config.services.nixsper.enable {
          # We use a user service because xdotool needs access to the user's X11 session
          systemd.user.services.nixsper = {
            description = "Nixsper Voice Typing Daemon";
            wantedBy = [ "graphical-session.target" ];
            partOf = [ "graphical-session.target" ];
            serviceConfig = {
              ExecStart =
                "${config.services.nixsper.package}/bin/nixsper-daemon";
              Restart = "always";
              RestartSec = "3";
            };
          };
        };
      };

      devShells.${system}.default = pkgs.mkShell {
        # Include the package dependencies + dev tools
        inputsFrom = [ nixsperPackage ];

        buildInputs = with pkgs; [
          python3Packages.virtualenv
          python3Packages.pip
          xdotool
          portaudio
          cudatoolkit
          cudaPackages.cudnn
        ];

        shellHook = ''
          export LD_LIBRARY_PATH=${
            pkgs.lib.makeLibraryPath [
              pkgs.cudatoolkit
              pkgs.cudaPackages.cudnn
            ]
          }:/run/opengl-driver/lib:$LD_LIBRARY_PATH
          echo "Nixsper dev shell."
          echo "Run 'nix run' to start the packaged daemon."
        '';
      };
    };
}
