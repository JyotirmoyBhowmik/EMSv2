import React from 'react';

const InfoIcon = ({ text }) => (
    <span className="tooltip-container" style={{ marginLeft: '6px', cursor: 'help', verticalAlign: 'middle', display: 'inline-flex' }}>
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" style={{ opacity: 0.7 }}>
            <circle cx="12" cy="12" r="10"></circle>
            <line x1="12" y1="16" x2="12" y2="12"></line>
            <line x1="12" y1="8" x2="12.01" y2="8"></line>
        </svg>
        <span className="tooltip-text">{text}</span>
    </span>
);

export default InfoIcon;
