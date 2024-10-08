package v2

import (
	"context"
	"fmt"
	"io/fs"
	"io/ioutil"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/stretchr/testify/require"

	"go.uber.org/zap/zapcore"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	utilrand "k8s.io/apimachinery/pkg/util/rand"

	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/envtest"
	logf "sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/log/zap"
	"sigs.k8s.io/yaml"
)

const yamlPathKey = "yaml-path"

func testUnmarshalDir(t *testing.T, dir string) []ClusterNetworkState {
	states := []ClusterNetworkState{}
	err := filepath.Walk(dir, func(path string, info fs.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if info.IsDir() && info.Name() == "policy" {
			return filepath.SkipDir
		}
		if info.IsDir() || filepath.Ext(info.Name()) != ".yml" || strings.Contains(info.Name(), "rollback") {
			return nil
		}
		state, err := ioutil.ReadFile(path)
		if err != nil {
			return fmt.Errorf("failed reading state '%s': %v", info.Name(), err)
		}
		// the macsec test are wrongly passing offload: off as boolean instea of
		// offload: "off"
		if strings.Contains(info.Name(), "macsec") {
			state = []byte(strings.ReplaceAll(string(state), "offload: off", `offload: "off"`))
		}
		clusterNetworkState := ClusterNetworkState{
			ObjectMeta: metav1.ObjectMeta{
				Name: generateName("test"),
				Annotations: map[string]string{
					yamlPathKey: path,
					"yaml-file": info.Name(),
				},
			},
		}
		err = yaml.Unmarshal(state, &clusterNetworkState.Spec.State)
		if err != nil {
			return err
		}
		states = append(states, clusterNetworkState)
		return nil
	})

	require.NoError(t, err, "must succeed reading states")
	require.NotEmpty(t, states, "missing test/integration output to test")
	return states
}
func TestCRD(t *testing.T) {
	tests := []struct {
		name, dir string
	}{
		{
			name: "examples",
			dir:  os.Getenv("NMSTATE_SOURCE_INSTALL_DIR") + "/examples",
		},
		{
			name: "e2e-dump",
			dir:  os.Getenv("NMSTATE_E2E_DUMP"),
		},
	}
	logf.SetLogger(zap.New(zap.Level(zapcore.DebugLevel)))

	t.Log("Installing apiserver and etcd")
	output, err := exec.Command("./setup-testenv.sh").CombinedOutput()
	require.NoError(t, err, output)

	// specify testEnv configuration
	testEnv := &envtest.Environment{
		BinaryAssetsDirectory: ".k8s/bin", CRDDirectoryPaths: []string{"."},
	}

	t.Log("Starting apiserver and etcd to deploy CRDs")
	cfg, err := testEnv.Start()
	defer func() {
		t.Log("Stoping apiserver and etcd")
		testEnv.Stop()
	}()
	require.NoError(t, err)

	err = AddToScheme(testEnv.Scheme)
	require.NoError(t, err)

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			states := testUnmarshalDir(t, tt.dir)

			cli, err := client.New(cfg, client.Options{Scheme: testEnv.Scheme})
			require.NoError(t, err)

			for _, state := range states {
				t.Run(state.Annotations["yaml-file"], func(t *testing.T) {
					err = cli.Create(context.Background(), &state)
					require.NoError(t, err, state.Annotations[yamlPathKey])
				})
			}
		})
	}
}

func generateName(base string) string {
	maxNameLength := 100
	randomLength := 10
	maxGeneratedNameLength := maxNameLength - randomLength
	if len(base) > maxGeneratedNameLength {
		base = base[:maxGeneratedNameLength]
	}
	return fmt.Sprintf("%s%s", base, utilrand.String(randomLength))
}
