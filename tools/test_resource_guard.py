import unittest
from resource_guard import Usage, violation
import ctypes
from pathlib import Path
from unittest.mock import Mock, patch
import resource_guard
import signal


class ResourceGuardTests(unittest.TestCase):
    def test_memory_aborts_at_boundary(self):
        self.assertIsNone(violation(99, 100, 1, 100, 50, 10))
        self.assertEqual(violation(100, 100, 1, 100, 50, 10), "Child memory limit reached")

    def test_disk_reserve_aborts_before_exhaustion(self):
        self.assertEqual(violation(10, 49, 1, 100, 50, 10), "Startup disk reserve reached")

    def test_timeout_is_bounded(self):
        self.assertEqual(violation(10, 100, 10, 100, 50, 10), "QA wall-clock limit reached")

    def test_sdk_memory_field_offset(self):
        self.assertEqual(Usage.footprint.offset, 72)
        self.assertEqual(ctypes.sizeof(Usage), 96)

    def test_limit_kills_only_spawned_process_group(self):
        process = Mock(pid=12345)
        process.poll.return_value = None
        def stop(pid, sig):
            self.assertEqual((pid, sig), (12345, signal.SIGKILL))
            process.poll.return_value = -9
        with patch.object(resource_guard.shutil, 'disk_usage', return_value=Mock(free=100)), \
             patch.object(resource_guard.subprocess, 'Popen', return_value=process), \
             patch.object(resource_guard, 'footprint', return_value=101), \
             patch.object(resource_guard.os, 'killpg', side_effect=stop) as kill, \
             patch('builtins.open', unittest.mock.mock_open()):
            with self.assertRaisesRegex(RuntimeError, 'memory limit'):
                resource_guard.run(['qa'], cwd=Path('.'), output=Path('ignored'), limit=100, minimum=50)
            kill.assert_called_once()
            process.wait.assert_called_once()

    def test_disk_reserve_prevents_launch(self):
        with patch.object(resource_guard.shutil, 'disk_usage', return_value=Mock(free=10)), \
             patch.object(resource_guard.subprocess, 'Popen') as launch:
            with self.assertRaisesRegex(RuntimeError, 'not started'):
                resource_guard.run(['qa'], cwd=Path('.'), output=Path('ignored'), minimum=50)
            launch.assert_not_called()

    def test_unavailable_memory_monitor_stops_child(self):
        process = Mock(pid=23456)
        process.poll.return_value = None
        with patch.object(resource_guard.shutil, 'disk_usage', return_value=Mock(free=100)), \
             patch.object(resource_guard.subprocess, 'Popen', return_value=process), \
             patch.object(resource_guard, 'footprint', side_effect=RuntimeError('monitor unavailable')), \
             patch.object(resource_guard.os, 'killpg') as kill, \
             patch('builtins.open', unittest.mock.mock_open()):
            with self.assertRaisesRegex(RuntimeError, 'monitor unavailable'):
                resource_guard.run(['qa'], cwd=Path('.'), output=Path('ignored'), minimum=50)
            kill.assert_called_once_with(23456, signal.SIGKILL)
            process.wait.assert_called_once()
