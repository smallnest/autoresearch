import AgentSelector from '../components/AgentSelector';
import { useSettingsStore } from '../stores/settingsStore';

function SettingsPage() {
  const { config, setMaxIterations, setPassingScore, resetToDefaults } = useSettingsStore();

  return (
    <div className="p-6">
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold">Settings</h1>
        <button
          type="button"
          onClick={resetToDefaults}
          className="px-3 py-1.5 text-sm font-medium text-gray-300 bg-gray-700 hover:bg-gray-600 rounded-lg"
        >
          Reset to Defaults
        </button>
      </div>
      <p className="text-gray-400 mb-6">Configure application preferences and agent settings.</p>

      <div className="max-w-2xl space-y-8">
        <section className="bg-gray-800 rounded-lg p-5 border border-gray-700">
          <h2 className="text-lg font-semibold mb-4">Agent Configuration</h2>
          <AgentSelector />
        </section>

        <section className="bg-gray-800 rounded-lg p-5 border border-gray-700">
          <h2 className="text-lg font-semibold mb-4">Run Parameters</h2>
          <div className="space-y-5">
            <div>
              <label htmlFor="maxIterations" className="block text-sm font-medium text-gray-300 mb-2">
                Maximum Iterations
              </label>
              <input
                type="number"
                id="maxIterations"
                min={1}
                max={100}
                value={config.maxIterations}
                onChange={(e) => setMaxIterations(parseInt(e.target.value) || 1)}
                className="w-full px-3 py-2 bg-gray-900 border border-gray-600 rounded-lg text-gray-100 focus:outline-none focus:border-blue-500"
              />
              <p className="mt-1 text-xs text-gray-500">
                Maximum number of iterations for one run (1-100, default: 42)
              </p>
            </div>

            <div>
              <label htmlFor="passingScore" className="block text-sm font-medium text-gray-300 mb-2">
                Passing Score
              </label>
              <input
                type="number"
                id="passingScore"
                min={0}
                max={100}
                value={config.passingScore}
                onChange={(e) => setPassingScore(parseInt(e.target.value) || 0)}
                className="w-full px-3 py-2 bg-gray-900 border border-gray-600 rounded-lg text-gray-100 focus:outline-none focus:border-blue-500"
              />
              <p className="mt-1 text-xs text-gray-500">
                Minimum score to pass review (0-100, default: 85)
              </p>
            </div>
          </div>
        </section>
      </div>
    </div>
  );
}

export default SettingsPage;
