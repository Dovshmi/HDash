package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"

	"github.com/atotto/clipboard"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/huh"
	"github.com/charmbracelet/lipgloss"
)

// --- State Management ---

type AppState struct {
	TargetIP string `json:"target_ip"`
	HunterIP string `json:"hunter_ip"`
}

func getConfigPath() string {
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".config", "hacker-dash", "state.json")
}

func loadState() AppState {
	path := getConfigPath()
	data, err := os.ReadFile(path)
	if err != nil {
		return AppState{}
	}
	var state AppState
	json.Unmarshal(data, &state)
	return state
}

func saveState(state AppState) error {
	path := getConfigPath()
	os.MkdirAll(filepath.Dir(path), 0755)
	data, _ := json.MarshalIndent(state, "", "  ")
	return os.WriteFile(path, data, 0644)
}

// --- Minimalist Styling ---

var (
	colorAccent = lipgloss.Color("#888888") // Subtle grey for labels
	colorValue  = lipgloss.Color("#FFFFFF") // White for values
	colorActive = lipgloss.Color("#E0E0E0") // Slightly brighter for active

	headerStyle = lipgloss.NewStyle().
			Foreground(colorValue).
			Bold(true).
			MarginLeft(2).
			Padding(0, 1)

	labelStyle = lipgloss.NewStyle().
			Foreground(colorAccent).
			Width(12)

	valueStyle = lipgloss.NewStyle().
			Foreground(colorValue).
			Bold(true)

	selectedStyle = lipgloss.NewStyle().
			Foreground(colorValue).
			Bold(true).
			Underline(true)

	statusStyle = lipgloss.NewStyle().
			Foreground(colorAccent).
			Italic(true)

	buttonStyle = lipgloss.NewStyle().
			Foreground(colorValue).
			Padding(0, 1).
			Bold(true)

	boxStyle = lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(colorAccent).
			Padding(1, 2).
			Margin(1, 2)
)

// --- Bubble Tea Model ---

type model struct {
	state      AppState
	cursor     int // 0: Target, 1: Hunter
	lastAction string
}

func (m model) Init() tea.Cmd {
	return nil
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "ctrl+c", "q":
			return m, tea.Quit
		case "up", "k":
			if m.cursor > 0 {
				m.cursor = 0
			}
			return m, nil
		case "down", "j":
			if m.cursor < 1 {
				m.cursor = 1
			}
			return m, nil
		case "enter":
			m.handleEnter()
			return m, nil
		case "c", "C":
			m.copyCurrent()
			return m, nil
		}
	}
	return m, nil
}

func (m *model) copyCurrent() {
	var currentIP string
	var label string
	if m.cursor == 0 {
		currentIP = m.state.TargetIP
		label = "TARGET"
	} else {
		currentIP = m.state.HunterIP
		label = "HUNTER"
	}

	if currentIP == "" {
		m.lastAction = fmt.Sprintf("%s is empty", label)
		return
	}

	clipboard.WriteAll(currentIP)
	m.lastAction = fmt.Sprintf("Copied %s to clipboard", label)
	os.WriteFile("/tmp/hacker_dash_target", []byte(fmt.Sprintf("export TARGET=%s", currentIP)), 0644)
}

func (m *model) handleEnter() {
	var label string
	if m.cursor == 0 {
		label = "TARGET"
	} else {
		label = "HUNTER"
	}

	fmt.Print("\n  [C] Copy  |  [E] Edit  |  [B] Back: ")
	var choice string
	fmt.Scanln(&choice)

	if choice == "c" || choice == "C" {
		m.copyCurrent()
	} else if choice == "e" || choice == "E" {
		var newIP string
		input := huh.NewInput().
			Title(fmt.Sprintf("Edit %s IP", label)).
			Value(&newIP)

		editForm := huh.NewForm(huh.NewGroup(input))
		if err := editForm.Run(); err == nil {
			if m.cursor == 0 {
				m.state.TargetIP = newIP
			} else {
				m.state.HunterIP = newIP
			}
			saveState(m.state)
			m.lastAction = fmt.Sprintf("Updated %s", label)
		}
	}
}

func (m model) View() string {
	title := headerStyle.Render("HACKER DASHBOARD")

	var tLine, hLine string
	if m.cursor == 0 {
		tLine = selectedStyle.Render(fmt.Sprintf("%-12s %s", "TARGET:", m.state.TargetIP))
		hLine = lipgloss.JoinHorizontal(lipgloss.Center, labelStyle.Render("HUNTER:"), valueStyle.Render(m.state.HunterIP))
	} else {
		tLine = lipgloss.JoinHorizontal(lipgloss.Center, labelStyle.Render("TARGET:"), valueStyle.Render(m.state.TargetIP))
		hLine = selectedStyle.Render(fmt.Sprintf("%-12s %s", "HUNTER:", m.state.HunterIP))
	}

	content := lipgloss.JoinVertical(
		lipgloss.Top,
		tLine,
		"",
		hLine,
	)

	status := statusStyle.Render(m.lastAction)
	btnQuit := buttonStyle.Render(" [Q] QUIT ")

	return boxStyle.Render(
		lipgloss.JoinVertical(
			lipgloss.Top,
			title,
			"",
			content,
			"",
			status,
			"",
			btnQuit,
		),
	)
}

func main() {
	state := loadState()
	m := model{
		state: state,
	}

	p := tea.NewProgram(m)
	if _, err := p.Run(); err != nil {
		fmt.Printf("Error running program: %v\n", err)
		os.Exit(1)
	}
}
