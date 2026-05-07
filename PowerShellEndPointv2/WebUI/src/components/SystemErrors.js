import React, { useState, useEffect, useCallback } from 'react';
import {
  Box, Typography, Paper, Table, TableBody, TableCell,
  TableContainer, TableHead, TableRow, Chip, IconButton,
  Tooltip, Dialog, DialogTitle, DialogContent, DialogActions, Button,
  LinearProgress, Alert, TextField
} from '@mui/material';
import {
  MdRefresh, MdCode, MdBugReport, MdDownload
} from 'react-icons/md';
import { format } from 'date-fns';
import api from '../services/api';

const SystemErrors = () => {
  const [errors, setErrors] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [selectedError, setSelectedError] = useState(null);
  const [search, setSearch] = useState('');

  const fetchErrors = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      // We leverage the existing audit API but filter specifically for frontend errors
      // Note: The API must support returning audit_api_requests or a specific error table.
      // We assume /api/admin/audit handles this.
      const response = await api.get('/admin/audit?type=ERROR');
      if (response.data && Array.isArray(response.data.logs)) {
        setErrors(response.data.logs.filter(log => log.method === 'ERROR'));
      } else {
        setErrors([]);
      }
    } catch (err) {
      setError(err.response?.data?.message || 'Failed to fetch system errors');
      // For demo purposes, we will populate with some dummy data if API fails to load real errors yet
      if (errors.length === 0) {
        setErrors([
          {
            request_id: 'e1',
            timestamp: new Date().toISOString(),
            user_id: 'TestAdmin',
            endpoint: '[FRONTEND CRASH] TypeError: Cannot read properties of undefined (reading "map")',
            ip_address: '10.0.0.5'
          }
        ]);
      }
    } finally {
      setLoading(false);
    }
  }, [errors.length]);

  useEffect(() => {
    fetchErrors();
    const interval = setInterval(fetchErrors, 30000);
    return () => clearInterval(interval);
  }, [fetchErrors]);

  const handleExport = () => {
    if (errors.length === 0) return;
    const csvRows = [];
    const headers = ['Timestamp', 'User', 'IP Address', 'Error Message'];
    csvRows.push(headers.join(','));

    filteredErrors.forEach(err => {
      const row = [
        err.timestamp,
        err.user_id,
        err.ip_address,
        `"${err.endpoint.replace(/"/g, '""')}"`
      ];
      csvRows.push(row.join(','));
    });

    const blob = new Blob([csvRows.join('\n')], { type: 'text/csv' });
    const url = window.URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.setAttribute('hidden', '');
    a.setAttribute('href', url);
    a.setAttribute('download', `System_Errors_Export_${format(new Date(), 'yyyyMMdd_HHmmss')}.csv`);
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
  };

  const filteredErrors = errors.filter(err =>
    err.endpoint?.toLowerCase().includes(search.toLowerCase()) ||
    err.user_id?.toLowerCase().includes(search.toLowerCase())
  );

  return (
    <Box sx={{ p: 3 }}>
      <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 3 }}>
        <Typography variant="h4" sx={{ display: 'flex', alignItems: 'center', fontWeight: 'bold' }}>
          <MdBugReport style={{ marginRight: '10px', color: '#dc3545' }} />
          Frontend System Errors
        </Typography>
        <Box sx={{ display: 'flex', gap: 2 }}>
          <Button
            variant="outlined"
            startIcon={<MdDownload />}
            onClick={handleExport}
            disabled={filteredErrors.length === 0}
          >
            Export CSV
          </Button>
          <IconButton onClick={fetchErrors} color="primary" title="Refresh">
            <MdRefresh size={28} />
          </IconButton>
        </Box>
      </Box>

      {error && (
        <Alert severity="warning" sx={{ mb: 3 }}>
          {error} - Showing cached/mock data.
        </Alert>
      )}

      <Paper sx={{ mb: 3, p: 2, display: 'flex', gap: 2 }}>
        <TextField
          fullWidth
          variant="outlined"
          placeholder="Search errors by message or user..."
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          size="small"
        />
      </Paper>

      <TableContainer component={Paper} sx={{ boxShadow: 3, borderRadius: 2 }}>
        {loading && <LinearProgress />}
        <Table>
          <TableHead sx={{ backgroundColor: '#f5f5f5' }}>
            <TableRow>
              <TableCell sx={{ fontWeight: 'bold' }}>Timestamp</TableCell>
              <TableCell sx={{ fontWeight: 'bold' }}>User</TableCell>
              <TableCell sx={{ fontWeight: 'bold' }}>IP Address</TableCell>
              <TableCell sx={{ fontWeight: 'bold' }}>Error Message</TableCell>
              <TableCell sx={{ fontWeight: 'bold', textAlign: 'center' }}>Stack Trace</TableCell>
            </TableRow>
          </TableHead>
          <TableBody>
            {filteredErrors.length === 0 ? (
              <TableRow>
                <TableCell colSpan={5} align="center" sx={{ py: 3 }}>
                  <Typography variant="body1" color="textSecondary">
                    No errors logged. Everything is running smoothly!
                  </Typography>
                </TableCell>
              </TableRow>
            ) : (
              filteredErrors.map((err) => (
                <TableRow key={err.request_id} hover>
                  <TableCell>
                    {format(new Date(err.timestamp), 'MMM dd, yyyy HH:mm:ss')}
                  </TableCell>
                  <TableCell>
                    <Chip label={err.user_id} size="small" color="primary" variant="outlined" />
                  </TableCell>
                  <TableCell>{err.ip_address}</TableCell>
                  <TableCell sx={{ maxWidth: '400px', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                    <Typography variant="body2" color="error" sx={{ fontFamily: 'monospace' }}>
                      {err.endpoint}
                    </Typography>
                  </TableCell>
                  <TableCell align="center">
                    <Tooltip title="View Stack Trace">
                      <IconButton color="primary" onClick={() => setSelectedError(err)}>
                        <MdCode />
                      </IconButton>
                    </Tooltip>
                  </TableCell>
                </TableRow>
              ))
            )}
          </TableBody>
        </Table>
      </TableContainer>

      {/* Stack Trace Dialog */}
      <Dialog open={!!selectedError} onClose={() => setSelectedError(null)} maxWidth="md" fullWidth>
        <DialogTitle sx={{ backgroundColor: '#dc3545', color: 'white', display: 'flex', alignItems: 'center' }}>
          <MdBugReport style={{ marginRight: '8px' }} /> Error Details
        </DialogTitle>
        <DialogContent dividers sx={{ backgroundColor: '#2d2d2d' }}>
          <Typography variant="body2" sx={{ fontFamily: 'monospace', color: '#ff6b6b', mb: 2, whiteSpace: 'pre-wrap' }}>
            {selectedError?.endpoint}
          </Typography>
          <Typography variant="caption" sx={{ color: '#a8a8a8' }}>
            User: {selectedError?.user_id} | IP: {selectedError?.ip_address} | Time: {selectedError && format(new Date(selectedError.timestamp), 'PPpp')}
          </Typography>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setSelectedError(null)} color="inherit">Close</Button>
        </DialogActions>
      </Dialog>
    </Box>
  );
};

export default SystemErrors;
