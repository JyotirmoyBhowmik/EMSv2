import React from 'react';
import { Box, Typography, Button } from '@mui/material';
import api from '../services/api';

class ErrorBoundary extends React.Component {
  constructor(props) {
    super(props);
    this.state = { hasError: false, error: null };
  }

  static getDerivedStateFromError(error) {
    return { hasError: true, error };
  }

  componentDidCatch(error, errorInfo) {
    // Send the error to the backend
    try {
      api.post('/audit/frontend-error', {
        message: error.message,
        stack: error.stack,
        componentStack: errorInfo?.componentStack,
        url: window.location.href,
        userAgent: navigator.userAgent
      }).catch(err => console.error("Failed to log error to backend", err));
    } catch (e) {
      console.error("Failed to invoke API to log error", e);
    }
  }

  handleReload = () => {
    window.location.reload();
  };

  render() {
    if (this.state.hasError) {
      return (
        <Box sx={{ p: 4, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', height: '100vh', backgroundColor: '#f8f9fa' }}>
          <Typography variant="h4" color="error" gutterBottom>
            Something went wrong.
          </Typography>
          <Typography variant="body1" color="textSecondary" sx={{ mb: 3 }}>
            A critical error occurred in the application. This incident has been logged.
          </Typography>
          <Button variant="contained" color="primary" onClick={this.handleReload}>
            Reload Application
          </Button>
        </Box>
      );
    }

    return this.props.children; 
  }
}

export default ErrorBoundary;
