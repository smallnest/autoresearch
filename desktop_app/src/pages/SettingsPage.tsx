import AgentSelector from '../components/AgentSelector';

function SettingsPage() {
  return (
    <div className="p-6">
      <h1 className="text-2xl font-bold mb-4">Settings</h1>
      <p className="text-gray-400 mb-6">Configure application preferences and agent settings.</p>
      
      <div className="max-w-2xl">
        <h2 className="text-lg font-semibold mb-4">Agent Configuration</h2>
        <AgentSelector />
      </div>
    </div>
  );
}

export default SettingsPage;
