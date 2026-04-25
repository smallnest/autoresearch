import AgentSelector from '../components/AgentSelector';

function SettingsPage() {
  return (
    <div className="p-6">
      <h1 className="text-2xl font-bold mb-4">设置</h1>
      <p className="text-gray-500 mb-6">配置应用偏好与 Agent 选择顺序。</p>
      
      <div className="max-w-2xl">
        <h2 className="text-lg font-semibold mb-4">Agent 配置</h2>
        <AgentSelector />
      </div>
    </div>
  );
}

export default SettingsPage;
