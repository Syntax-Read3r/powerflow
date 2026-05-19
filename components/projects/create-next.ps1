# ==============================================================================
# PowerFlow — Next.js Project Generator
# ==============================================================================
# Domain   : Projects
# File     : components/projects/create-next.ps1
# Purpose  : Scaffold a professional Next.js app with PostgreSQL, Prisma, Docker, and CI/CD
# Functions: create-next, create-n
# Depends  : config/PowerFlow.settings.ps1
# ==============================================================================

function create-next {
    # Check if Node.js and npm are available
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
        Write-Host "❌ Node.js is required but not found" -ForegroundColor Red
        Write-Host "💡 Install Node.js from: https://nodejs.org/" -ForegroundColor DarkGray
        return
    }

    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        Write-Host "❌ npm is required but not found" -ForegroundColor Red
        return
    }

    # Check Node.js version (require 18+)
    $nodeVersion = node --version
    $majorVersion = [int]($nodeVersion -replace 'v(\d+)\..*', '$1')
    if ($majorVersion -lt 18) {
        Write-Host "❌ Node.js 18+ is required. Current version: $nodeVersion" -ForegroundColor Red
        Write-Host "💡 Update Node.js from: https://nodejs.org/" -ForegroundColor DarkGray
        return
    }

    # Step 1: Get project name
    $formLines = @(
        "",
        "🚀 Next.js Professional Project Creator v2.2",
        "═══════════════════════════════════════════",
        "",
        "📦 Features included:",
        "   ⚡ Next.js 15+ with App Router",
        "   📘 TypeScript configuration",
        "   🎨 Tailwind CSS styling",
        "   🔍 ESLint code quality",
        "   📁 Professional src/ structure",
        "   🗄️  PostgreSQL + Prisma ORM",
        "   🐳 FIXED Docker (Debian-based)",
        "   🚀 GitHub Actions CI/CD",
        "   📄 Functional pages with real data",
        "   👥 Sample user database with API",
        "",
        "💬 Type your project name above and press Enter"
    )

    # Launch fzf with --print-query to get typed input
    $fzfOutput = $formLines | fzf `
        --ansi `
        --reverse `
        --border=rounded `
        --height=70% `
        --prompt="📝 Project Name: " `
        --header="🚀 Next.js Professional Project Creator v2.2" `
        --header-first `
        --color="header:bold:blue,prompt:bold:green,border:cyan,spinner:yellow" `
        --margin=1 `
        --padding=1 `
        --print-query `
        --expect=enter

    # Extract the project name from fzf output
    $projectName = ""
    if ($fzfOutput) {
        $lines = @($fzfOutput)
        if ($lines.Count -gt 0) {
            $projectName = $lines[0].Trim()
        }
    }

    # Validate project name
    if ([string]::IsNullOrWhiteSpace($projectName)) {
        Write-Host "❌ Project creation cancelled - no name provided" -ForegroundColor Yellow
        return
    }

    # Validate project name format
    if ($projectName -notmatch '^[a-z0-9][a-z0-9-]*[a-z0-9]$|^[a-z0-9]$') {
        Write-Host "❌ Invalid project name: $projectName" -ForegroundColor Red
        Write-Host "💡 Project name must:" -ForegroundColor DarkGray
        Write-Host "   • Start and end with lowercase letter or number" -ForegroundColor DarkGray
        Write-Host "   • Only contain lowercase letters, numbers, and hyphens" -ForegroundColor DarkGray
        Write-Host "   • Examples: my-app, todo-list, user-dashboard" -ForegroundColor DarkGray
        return
    }

    # Check if directory already exists
    if (Test-Path $projectName) {
        Write-Host "❌ Directory '$projectName' already exists" -ForegroundColor Red
        return
    }

    Write-Host ""
    Write-Host "🚀 Creating professional Next.js project: $projectName" -ForegroundColor Cyan
    Write-Host "🗄️  Database: PostgreSQL with Prisma ORM + Sample Users" -ForegroundColor Cyan
    Write-Host "════════════════════════════════════════════════════" -ForegroundColor Cyan

    # Step 2: Create Next.js app
    Write-Host ""
    Write-Host "📦 [1/9] Creating Next.js application..." -ForegroundColor Yellow

    $createCommand = "npx create-next-app@latest $projectName --typescript --tailwind --eslint --app --src-dir --yes"
    Write-Host "   Running: $createCommand" -ForegroundColor DarkGray

    Invoke-Expression $createCommand
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Failed to create Next.js app" -ForegroundColor Red
        return
    }
    Write-Host "✅ Next.js application created successfully" -ForegroundColor Green

    # Navigate to project directory
    Set-Location $projectName
    Write-Host "📁 Navigated to project directory" -ForegroundColor Cyan

    # Step 3: Create directory structure
    Write-Host ""
    Write-Host "📁 [2/9] Creating directory structure..." -ForegroundColor Yellow

    $directories = @(
        "src/components/ui",
        "src/components/common",
        "src/components/layout",
        "src/lib/utils",
        "src/lib/hooks",
        "src/lib/auth",
        "src/lib/database",
        "src/types/database",
        "prisma",
        "prisma/migrations",
        "docs",
        ".github/workflows"
    )

    foreach ($dir in $directories) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-Host "   📂 Created: $dir" -ForegroundColor Green
    }

    # Step 4: Create Prisma schema with User model
    Write-Host ""
    Write-Host "🗄️  [3/9] Creating database configuration..." -ForegroundColor Yellow

    @"
// Prisma schema for PostgreSQL
generator client {
  provider = "prisma-client-js"
}

datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}

model User {
  id        String   @id @default(cuid())
  username  String   @unique
  name      String
  age       Int
  email     String?  @unique
  createdAt DateTime @default(now())
  updatedAt DateTime @updatedAt

  @@map("users")
}
"@ | Set-Content "prisma/schema.prisma"

    # Create Prisma client
    @"
import { PrismaClient } from '@prisma/client'

const globalForPrisma = globalThis as unknown as {
  prisma: PrismaClient | undefined
}

export const prisma =
  globalForPrisma.prisma ??
  new PrismaClient({
    log: ['query'],
  })

if (process.env.NODE_ENV !== 'production') globalForPrisma.prisma = prisma
"@ | Set-Content "src/lib/database/prisma.ts"

    # Create database seed file with FIXED disconnect method (PowerShell dollar sign escaped)
    @'
import { PrismaClient } from '@prisma/client'

const prisma = new PrismaClient()

async function main() {
  await prisma.user.deleteMany()

  const user1 = await prisma.user.create({
    data: {
      username: 'johndoe',
      name: 'John Doe',
      age: 28,
      email: 'john.doe@example.com',
    },
  })

  const user2 = await prisma.user.create({
    data: {
      username: 'janebrown',
      name: 'Jane Brown',
      age: 34,
      email: 'jane.brown@example.com',
    },
  })

  const user3 = await prisma.user.create({
    data: {
      username: 'mikejohnson',
      name: 'Mike Johnson',
      age: 29,
      email: 'mike.johnson@example.com',
    },
  })

  console.log('Seeded 3 users successfully')
  console.log('Created:', user1.username)
  console.log('Created:', user2.username)
  console.log('Created:', user3.username)
}

main()
  .catch((e) => {
    console.error('Seeding failed:', e)
    process.exit(1)
  })
  .finally(async () => {
    await prisma.$disconnect()
  })
'@ | Set-Content "prisma/seed.ts"

    # Create dual environment files for local and Docker development

    # .env.local (for local development - uses localhost)
    @"
# Database (Local Development)
DATABASE_URL="postgresql://${script:DB_USERNAME}:${script:DB_PASSWORD}@localhost:5432/${projectName}?schema=public"

# App Configuration
NEXT_PUBLIC_APP_URL=http://localhost:3000
NEXTAUTH_SECRET=your-secret-here
NEXTAUTH_URL=http://localhost:3000

# Add your environment variables here
"@ | Set-Content ".env.local"

    # .env.docker (for Docker development - uses db service name)
    @"
# Database (Docker Development)
DATABASE_URL="postgresql://${script:DB_USERNAME}:${script:DB_PASSWORD}@db:5432/${projectName}?schema=public"

# App Configuration
NEXT_PUBLIC_APP_URL=http://localhost:3000
NEXTAUTH_SECRET=your-secret-here
NEXTAUTH_URL=http://localhost:3000

# Add your environment variables here
"@ | Set-Content ".env.docker"

    # Reference template (copy from local)
    Copy-Item ".env.local" ".env.example" -Force

    Write-Host "✅ Database configuration created for PostgreSQL" -ForegroundColor Green

    # Step 5: Create API routes and pages
    Write-Host ""
    Write-Host "📄 [4/9] Creating API routes and pages..." -ForegroundColor Yellow

    # API route for users
    New-Item -ItemType Directory -Path "src/app/api/users" -Force | Out-Null
    @"
import { NextRequest, NextResponse } from 'next/server'
import { prisma } from '@/lib/database/prisma'

export async function GET() {
  try {
    const users = await prisma.user.findMany({
      orderBy: {
        createdAt: 'desc'
      }
    })

    return NextResponse.json({
      success: true,
      data: users,
      count: users.length
    })
  } catch (error) {
    console.error('❌ Failed to fetch users:', error)
    return NextResponse.json(
      {
        success: false,
        error: 'Failed to fetch users'
      },
      { status: 500 }
    )
  }
}

export async function POST(request: NextRequest) {
  try {
    const body = await request.json()
    const { username, name, age, email } = body

    if (!username || !name || !age) {
      return NextResponse.json(
        {
          success: false,
          error: 'Username, name, and age are required'
        },
        { status: 400 }
      )
    }

    const user = await prisma.user.create({
      data: {
        username,
        name,
        age: parseInt(age),
        email: email || null,
      },
    })

    return NextResponse.json({
      success: true,
      data: user,
      message: 'User created successfully'
    })
  } catch (error) {
    console.error('❌ Failed to create user:', error)
    return NextResponse.json(
      {
        success: false,
        error: 'Failed to create user'
      },
      { status: 500 }
    )
  }
}
"@ | Set-Content "src/app/api/users/route.ts"

    # User types
    @"
export interface User {
  id: string
  username: string
  name: string
  age: number
  email?: string | null
  createdAt: Date
  updatedAt: Date
}

export interface ApiResponse<T> {
  success: boolean
  data?: T
  error?: string
  message?: string
  count?: number
}
"@ | Set-Content "src/types/database/user.ts"

    # Home page with user data
    @"
import Link from 'next/link'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { UserList } from '@/components/common/UserList'

export default function HomePage() {
  return (
    <div className="min-h-screen bg-gradient-to-b from-blue-50 to-white">
      <div className="container mx-auto px-4 py-8">
        {/* Header */}
        <div className="text-center mb-12">
          <h1 className="text-4xl font-bold text-gray-900 mb-4">
            Welcome to Your App
          </h1>
          <p className="text-xl text-gray-600 max-w-2xl mx-auto">
            A professional Next.js application with PostgreSQL, Prisma, and real user data.
          </p>
        </div>

        {/* Quick Stats */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-6 mb-12">
          <Card>
            <CardHeader className="text-center">
              <CardTitle className="text-2xl">⚡</CardTitle>
              <CardDescription>Next.js 15+</CardDescription>
            </CardHeader>
            <CardContent>
              <p className="text-center text-sm text-gray-600">
                Modern React framework with App Router
              </p>
            </CardContent>
          </Card>

          <Card>
            <CardHeader className="text-center">
              <CardTitle className="text-2xl">🗄️</CardTitle>
              <CardDescription>PostgreSQL + Prisma</CardDescription>
            </CardHeader>
            <CardContent>
              <p className="text-center text-sm text-gray-600">
                Type-safe database with live user data
              </p>
            </CardContent>
          </Card>

          <Card>
            <CardHeader className="text-center">
              <CardTitle className="text-2xl">🐳</CardTitle>
              <CardDescription>Docker Ready</CardDescription>
            </CardHeader>
            <CardContent>
              <p className="text-center text-sm text-gray-600">
                Containerized development environment
              </p>
            </CardContent>
          </Card>
        </div>

        {/* Live User Data */}
        <Card className="mb-8">
          <CardHeader>
            <CardTitle>👥 Live User Data</CardTitle>
            <CardDescription>
              Real users from your PostgreSQL database
            </CardDescription>
          </CardHeader>
          <CardContent>
            <UserList />
          </CardContent>
        </Card>

        {/* Navigation */}
        <div className="text-center space-x-4">
          <Button asChild>
            <Link href="/users">View All Users</Link>
          </Button>
          <Button variant="outline" asChild>
            <Link href="/about">About This App</Link>
          </Button>
        </div>
      </div>
    </div>
  )
}
"@ | Set-Content "src/app/page.tsx"

    # Users page
    New-Item -ItemType Directory -Path "src/app/users" -Force | Out-Null
    @"
import { UserList } from '@/components/common/UserList'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import Link from 'next/link'

export default function UsersPage() {
  return (
    <div className="min-h-screen bg-gray-50">
      <div className="container mx-auto px-4 py-8">
        {/* Header */}
        <div className="mb-8">
          <div className="flex items-center justify-between">
            <div>
              <h1 className="text-3xl font-bold text-gray-900">Users</h1>
              <p className="text-gray-600 mt-2">
                Manage and view all users in the system
              </p>
            </div>
            <Button asChild>
              <Link href="/">← Back to Home</Link>
            </Button>
          </div>
        </div>

        {/* Users Card */}
        <Card>
          <CardHeader>
            <CardTitle>All Users</CardTitle>
            <CardDescription>
              Users stored in PostgreSQL database via Prisma ORM
            </CardDescription>
          </CardHeader>
          <CardContent>
            <UserList showDetails />
          </CardContent>
        </Card>
      </div>
    </div>
  )
}
"@ | Set-Content "src/app/users/page.tsx"

    # About page
    New-Item -ItemType Directory -Path "src/app/about" -Force | Out-Null
    @"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import Link from 'next/link'

export default function AboutPage() {
  return (
    <div className="min-h-screen bg-gray-50">
      <div className="container mx-auto px-4 py-8">
        {/* Header */}
        <div className="mb-8">
          <div className="flex items-center justify-between">
            <div>
              <h1 className="text-3xl font-bold text-gray-900">About</h1>
              <p className="text-gray-600 mt-2">
                Learn about this Next.js application
              </p>
            </div>
            <Button asChild>
              <Link href="/">← Back to Home</Link>
            </Button>
          </div>
        </div>

        {/* About Content */}
        <div className="grid gap-6">
          <Card>
            <CardHeader>
              <CardTitle>🚀 Technology Stack</CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div>
                  <h3 className="font-semibold mb-2">Frontend</h3>
                  <ul className="text-sm text-gray-600 space-y-1">
                    <li>• Next.js 15+ with App Router</li>
                    <li>• TypeScript for type safety</li>
                    <li>• Tailwind CSS for styling</li>
                    <li>• React Server Components</li>
                  </ul>
                </div>
                <div>
                  <h3 className="font-semibold mb-2">Backend</h3>
                  <ul className="text-sm text-gray-600 space-y-1">
                    <li>• PostgreSQL database</li>
                    <li>• Prisma ORM</li>
                    <li>• API Routes</li>
                    <li>• Server-side data fetching</li>
                  </ul>
                </div>
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>📦 Features</CardTitle>
            </CardHeader>
            <CardContent>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div>
                  <h3 className="font-semibold mb-2">Development</h3>
                  <ul className="text-sm text-gray-600 space-y-1">
                    <li>• Hot reload development</li>
                    <li>• ESLint code quality</li>
                    <li>• TypeScript intellisense</li>
                    <li>• Docker containerization</li>
                  </ul>
                </div>
                <div>
                  <h3 className="font-semibold mb-2">Production</h3>
                  <ul className="text-sm text-gray-600 space-y-1">
                    <li>• Optimized builds</li>
                    <li>• Database migrations</li>
                    <li>• CI/CD pipeline</li>
                    <li>• Environment management</li>
                  </ul>
                </div>
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>🗄️ Database Schema</CardTitle>
            </CardHeader>
            <CardContent>
              <div className="bg-gray-50 p-4 rounded-lg">
                <h3 className="font-semibold mb-2">User Model</h3>
                <pre className="text-sm text-gray-700">
{`model User {
  id        String   @id @default(cuid())
  username  String   @unique
  name      String
  age       Int
  email     String?  @unique
  createdAt DateTime @default(now())
  updatedAt DateTime @updatedAt
}`}
                </pre>
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>🚀 Getting Started</CardTitle>
            </CardHeader>
            <CardContent>
              <div className="space-y-4">
                <div>
                  <h3 className="font-semibold mb-2">Development Commands</h3>
                  <div className="bg-gray-50 p-4 rounded-lg space-y-2">
                    <code className="block text-sm">npm run docker:dev</code>
                    <code className="block text-sm">npm run prisma:studio</code>
                    <code className="block text-sm">npm run dev</code>
                  </div>
                </div>
                <div>
                  <h3 className="font-semibold mb-2">Database Commands</h3>
                  <div className="bg-gray-50 p-4 rounded-lg space-y-2">
                    <code className="block text-sm">npm run prisma:migrate</code>
                    <code className="block text-sm">npm run prisma:seed</code>
                    <code className="block text-sm">npm run prisma:generate</code>
                  </div>
                </div>
              </div>
            </CardContent>
          </Card>
        </div>
      </div>
    </div>
  )
}
"@ | Set-Content "src/app/about/page.tsx"

    # Create UI components
    New-Item -ItemType Directory -Path "src/components/ui" -Force | Out-Null

    # Card component
    @"
import * as React from "react"
import { cn } from "@/lib/utils"

const Card = React.forwardRef<
  HTMLDivElement,
  React.HTMLAttributes<HTMLDivElement>
>(({ className, ...props }, ref) => (
  <div
    ref={ref}
    className={cn(
      "rounded-lg border bg-card text-card-foreground shadow-sm",
      className
    )}
    {...props}
  />
))
Card.displayName = "Card"

const CardHeader = React.forwardRef<
  HTMLDivElement,
  React.HTMLAttributes<HTMLDivElement>
>(({ className, ...props }, ref) => (
  <div
    ref={ref}
    className={cn("flex flex-col space-y-1.5 p-6", className)}
    {...props}
  />
))
CardHeader.displayName = "CardHeader"

const CardTitle = React.forwardRef<
  HTMLParagraphElement,
  React.HTMLAttributes<HTMLHeadingElement>
>(({ className, ...props }, ref) => (
  <h3
    ref={ref}
    className={cn(
      "text-2xl font-semibold leading-none tracking-tight",
      className
    )}
    {...props}
  />
))
CardTitle.displayName = "CardTitle"

const CardDescription = React.forwardRef<
  HTMLParagraphElement,
  React.HTMLAttributes<HTMLParagraphElement>
>(({ className, ...props }, ref) => (
  <p
    ref={ref}
    className={cn("text-sm text-muted-foreground", className)}
    {...props}
  />
))
CardDescription.displayName = "CardDescription"

const CardContent = React.forwardRef<
  HTMLDivElement,
  React.HTMLAttributes<HTMLDivElement>
>(({ className, ...props }, ref) => (
  <div ref={ref} className={cn("p-6 pt-0", className)} {...props} />
))
CardContent.displayName = "CardContent"

const CardFooter = React.forwardRef<
  HTMLDivElement,
  React.HTMLAttributes<HTMLDivElement>
>(({ className, ...props }, ref) => (
  <div
    ref={ref}
    className={cn("flex items-center p-6 pt-0", className)}
    {...props}
  />
))
CardFooter.displayName = "CardFooter"

export { Card, CardHeader, CardFooter, CardTitle, CardDescription, CardContent }
"@ | Set-Content "src/components/ui/card.tsx"

    # Button component
    @"
import * as React from "react"
import { Slot } from "@radix-ui/react-slot"
import { cva, type VariantProps } from "class-variance-authority"
import { cn } from "@/lib/utils"

const buttonVariants = cva(
  "inline-flex items-center justify-center whitespace-nowrap rounded-md text-sm font-medium ring-offset-background transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:pointer-events-none disabled:opacity-50",
  {
    variants: {
      variant: {
        default: "bg-primary text-primary-foreground hover:bg-primary/90",
        destructive:
          "bg-destructive text-destructive-foreground hover:bg-destructive/90",
        outline:
          "border border-input bg-background hover:bg-accent hover:text-accent-foreground",
        secondary:
          "bg-secondary text-secondary-foreground hover:bg-secondary/80",
        ghost: "hover:bg-accent hover:text-accent-foreground",
        link: "text-primary underline-offset-4 hover:underline",
      },
      size: {
        default: "h-10 px-4 py-2",
        sm: "h-9 rounded-md px-3",
        lg: "h-11 rounded-md px-8",
        icon: "h-10 w-10",
      },
    },
    defaultVariants: {
      variant: "default",
      size: "default",
    },
  }
)

export interface ButtonProps
  extends React.ButtonHTMLAttributes<HTMLButtonElement>,
    VariantProps<typeof buttonVariants> {
  asChild?: boolean
}

const Button = React.forwardRef<HTMLButtonElement, ButtonProps>(
  ({ className, variant, size, asChild = false, ...props }, ref) => {
    const Comp = asChild ? Slot : "button"
    return (
      <Comp
        className={cn(buttonVariants({ variant, size, className }))}
        ref={ref}
        {...props}
      />
    )
  }
)
Button.displayName = "Button"

export { Button, buttonVariants }
"@ | Set-Content "src/components/ui/button.tsx"

    # UserList component
    @"
'use client'

import { useState, useEffect } from 'react'
import { User, ApiResponse } from '@/types/database/user'

interface UserListProps {
  showDetails?: boolean
}

export function UserList({ showDetails = false }: UserListProps) {
  const [users, setUsers] = useState<User[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    async function fetchUsers() {
      try {
        const response = await fetch('/api/users')
        const data: ApiResponse<User[]> = await response.json()

        if (data.success && data.data) {
          setUsers(data.data)
        } else {
          setError(data.error || 'Failed to fetch users')
        }
      } catch (err) {
        setError('Network error: Could not fetch users')
        console.error('Failed to fetch users:', err)
      } finally {
        setLoading(false)
      }
    }

    fetchUsers()
  }, [])

  if (loading) {
    return (
      <div className="flex items-center justify-center py-8">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600"></div>
        <span className="ml-2 text-gray-600">Loading users...</span>
      </div>
    )
  }

  if (error) {
    return (
      <div className="text-center py-8">
        <div className="text-red-600 mb-2">❌ {error}</div>
        <div className="text-sm text-gray-500">
          Make sure your database is running and seeded
        </div>
      </div>
    )
  }

  if (users.length === 0) {
    return (
      <div className="text-center py-8">
        <div className="text-gray-600 mb-2">No users found</div>
        <div className="text-sm text-gray-500">
          Run <code className="bg-gray-100 px-2 py-1 rounded">npm run prisma:seed</code> to add sample data
        </div>
      </div>
    )
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h3 className="text-lg font-semibold">
          {users.length} User{users.length !== 1 ? 's' : ''}
        </h3>
        <div className="text-sm text-gray-500">
          Live from PostgreSQL
        </div>
      </div>

      <div className="grid gap-4">
        {users.map((user) => (
          <div
            key={user.id}
            className="border rounded-lg p-4 hover:shadow-md transition-shadow"
          >
            <div className="flex items-center justify-between">
              <div className="flex items-center space-x-3">
                <div className="w-10 h-10 bg-blue-100 rounded-full flex items-center justify-center">
                  <span className="text-blue-600 font-semibold">
                    {user.name.charAt(0).toUpperCase()}
                  </span>
                </div>
                <div>
                  <h4 className="font-semibold text-gray-900">{user.name}</h4>
                  <p className="text-sm text-gray-600">@{user.username}</p>
                </div>
              </div>
              <div className="text-right">
                <div className="text-lg font-semibold text-blue-600">
                  {user.age} years
                </div>
                {showDetails && user.email && (
                  <div className="text-sm text-gray-500">{user.email}</div>
                )}
              </div>
            </div>

            {showDetails && (
              <div className="mt-3 pt-3 border-t text-xs text-gray-500">
                <div>ID: {user.id}</div>
                <div>Created: {new Date(user.createdAt).toLocaleDateString()}</div>
              </div>
            )}
          </div>
        ))}
      </div>
    </div>
  )
}
"@ | Set-Content "src/components/common/UserList.tsx"

    # Utils
    @"
import { type ClassValue, clsx } from "clsx"
import { twMerge } from "tailwind-merge"

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}
"@ | Set-Content "src/lib/utils/index.ts"

    Write-Host "✅ Functional pages and components created" -ForegroundColor Green

    # Step 6: Create FIXED Docker configuration (Debian-based)
    Write-Host ""
    Write-Host "🐳 [5/9] Creating FIXED Docker configuration..." -ForegroundColor Yellow

    # Fixed Production Dockerfile (Debian-based)
    @"
# Production Dockerfile - FIXED for lightningcss compatibility
FROM node:20-slim AS base

# Install dependencies only when needed
FROM base AS deps
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    make \
    g++ \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy package files
COPY package.json package-lock.json* ./
RUN npm ci --only=production && npm cache clean --force

# Rebuild the source code only when needed
FROM base AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Build the application
ENV NEXT_TELEMETRY_DISABLED 1
RUN npm run build

# Production image, copy all the files and run next
FROM base AS runner
WORKDIR /app

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED 1

RUN groupadd --system --gid 1001 nodejs
RUN useradd --system --uid 1001 nextjs

COPY --from=builder /app/public ./public

# Set the correct permission for prerender cache
RUN mkdir .next
RUN chown nextjs:nodejs .next

# Copy built application
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

USER nextjs

EXPOSE 3000

ENV PORT=3000

CMD ["node", "server.js"]
"@ | Set-Content "Dockerfile"

    # Fixed Development Dockerfile
    @"
# Development Dockerfile - FIXED for lightningcss compatibility and Prisma
FROM node:20-slim

# Install additional packages needed for native modules
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    make \
    g++ \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install dependencies
COPY package.json package-lock.json* ./

# Clear npm cache and install
RUN npm cache clean --force
RUN npm ci

# Copy source code and schema
COPY . .

# Generate Prisma client (FIXED)
RUN npx prisma generate

EXPOSE 3000

CMD ["npm", "run", "dev"]
"@ | Set-Content "Dockerfile.dev"

    # Docker compose with PostgreSQL using official documentation best practices
    @"
version: '3.8'

services:
  app:
    build:
      context: .
      dockerfile: Dockerfile
    ports:
      - "3000:3000"
    environment:
      - NODE_ENV=production
      - DATABASE_URL=postgresql://${script:DB_USERNAME}:${script:DB_PASSWORD}@db:5432/${projectName}?schema=public
    depends_on:
      db:
        condition: service_healthy
    restart: always

  db:
    image: postgres:17.5
    restart: always
    shm_size: 128mb
    environment:
      POSTGRES_PASSWORD: "@Crix13Mix01"
      POSTGRES_USER: postgres
      POSTGRES_DB: ${projectName}
    ports:
      - "5432:5432"
    volumes:
      - ./docker-data/db:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 10s
      timeout: 5s
      retries: 5
"@ | Set-Content "docker-compose.yml"

    # Development Docker compose with automatic database setup using PostgreSQL best practices
    @"
version: '3.8'

services:
  app:
    build:
      context: .
      dockerfile: Dockerfile.dev
    ports:
      - "3000:3000"
    volumes:
      - .:/app
      - /app/node_modules
      - /app/.next
    env_file:
      - .env.docker
    depends_on:
      db:
        condition: service_healthy
    command: sh -c "npm run db:push:docker && npm run db:seed:docker && npm run dev"
    restart: unless-stopped

  db:
    image: postgres:17.5
    restart: always
    shm_size: 128mb
    environment:
      POSTGRES_PASSWORD: "@Crix13Mix01"
      POSTGRES_USER: postgres
      POSTGRES_DB: ${projectName}_dev
    ports:
      - "5432:5432"
    volumes:
      - ./docker-data/db-dev:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 10s
      timeout: 5s
      retries: 5
"@ | Set-Content "docker-compose-dev.yml"

    Write-Host "✅ FIXED Docker configuration created (Debian-based)" -ForegroundColor Green

    # Step 7: Create next.config with standalone output
    Write-Host ""
    Write-Host "⚙️  [6/9] Creating Next.js configuration..." -ForegroundColor Yellow

    @"
/** @type {import('next').NextConfig} */
const nextConfig = {
  output: 'standalone',
  experimental: {
    optimizeCss: false, // Helps avoid CSS build issues
  },
}

module.exports = nextConfig
"@ | Set-Content "next.config.js"

    Write-Host "✅ Next.js configuration created" -ForegroundColor Green

    # Step 8: Update package.json with all necessary scripts and dependencies
    Write-Host ""
    Write-Host "📦 [7/9] Updating package.json..." -ForegroundColor Yellow

    # Read current package.json
    $packageJson = Get-Content "package.json" | ConvertFrom-Json -AsHashtable

    # Add all necessary scripts
    $packageJson.scripts["type-check"] = "tsc --noEmit"
    $packageJson.scripts["docker:dev"] = "docker-compose -f docker-compose-dev.yml up --build"
    $packageJson.scripts["docker:dev:clean"] = "docker-compose -f docker-compose-dev.yml build --no-cache && docker-compose -f docker-compose-dev.yml up"
    $packageJson.scripts["docker:build"] = "docker-compose build"
    $packageJson.scripts["docker:start"] = "docker-compose up -d"
    $packageJson.scripts["docker:stop"] = "docker-compose down"
    $packageJson.scripts["docker:logs"] = "docker-compose logs -f"
    $packageJson.scripts["prisma:generate"] = "prisma generate"
    $packageJson.scripts["prisma:push"] = "prisma db push"
    $packageJson.scripts["prisma:migrate"] = "prisma migrate dev"
    $packageJson.scripts["prisma:studio"] = "prisma studio"
    $packageJson.scripts["prisma:seed"] = "tsx prisma/seed.ts"
    $packageJson.scripts["prisma:reset"] = "prisma migrate reset"

    # Environment-aware database scripts (FIXED)
    $packageJson.scripts["db:push:local"] = "dotenv -e .env.local -- prisma db push"
    $packageJson.scripts["db:push:docker"] = "dotenv -e .env.docker -- prisma db push"
    $packageJson.scripts["db:seed:local"] = "dotenv -e .env.local -- tsx prisma/seed.ts"
    $packageJson.scripts["db:seed:docker"] = "dotenv -e .env.docker -- tsx prisma/seed.ts"
    $packageJson.scripts["db:setup:local"] = "npm run prisma:generate && npm run db:push:local && npm run db:seed:local"
    $packageJson.scripts["db:setup:docker"] = "npm run prisma:generate && npm run db:push:docker && npm run db:seed:docker"

    # Add prisma seed config
    $packageJson["prisma"] = @{
        "seed" = "tsx prisma/seed.ts"
    }

    # Save updated package.json
    $packageJson | ConvertTo-Json -Depth 10 | Set-Content "package.json"

    Write-Host "✅ Package.json updated with scripts" -ForegroundColor Green

    # Step 9: Install dependencies
    Write-Host ""
    Write-Host "🛠️  [8/9] Installing dependencies..." -ForegroundColor Yellow

    $dependencies = @("@prisma/client", "clsx", "class-variance-authority", "tailwind-merge", "@radix-ui/react-slot")
    $devDependencies = @("prisma", "@types/node", "tsx", "dotenv-cli")

    Write-Host "   Installing dependencies: $($dependencies -join ', ')" -ForegroundColor DarkGray
    $installCommand = "npm install " + ($dependencies -join " ")
    Invoke-Expression $installCommand

    if ($LASTEXITCODE -eq 0) {
        Write-Host "   Installing dev dependencies: $($devDependencies -join ', ')" -ForegroundColor DarkGray
        $installDevCommand = "npm install --save-dev " + ($devDependencies -join " ")
        Invoke-Expression $installDevCommand
    }

    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Dependencies installed successfully" -ForegroundColor Green
    } else {
        Write-Host "⚠️  Some dependencies may have failed to install" -ForegroundColor Yellow
    }

    # Step 10: Update CSS
    Write-Host ""
    Write-Host "🎨 [9/9] Updating CSS..." -ForegroundColor Yellow

    @"
@tailwind base;
@tailwind components;
@tailwind utilities;

@layer base {
  :root {
    --background: 0 0% 100%;
    --foreground: 222.2 84% 4.9%;
    --card: 0 0% 100%;
    --card-foreground: 222.2 84% 4.9%;
    --popover: 0 0% 100%;
    --popover-foreground: 222.2 84% 4.9%;
    --primary: 222.2 47.4% 11.2%;
    --primary-foreground: 210 40% 98%;
    --secondary: 210 40% 96.1%;
    --secondary-foreground: 222.2 47.4% 11.2%;
    --muted: 210 40% 98%;
    --muted-foreground: 215.4 16.3% 46.9%;
    --accent: 210 40% 96.1%;
    --accent-foreground: 222.2 47.4% 11.2%;
    --destructive: 0 84.2% 60.2%;
    --destructive-foreground: 210 40% 98%;
    --border: 214.3 31.8% 91.4%;
    --input: 214.3 31.8% 91.4%;
    --ring: 222.2 84% 4.9%;
    --radius: 0.5rem;
  }

  .dark {
    --background: 222.2 84% 4.9%;
    --foreground: 210 40% 98%;
    --card: 222.2 84% 4.9%;
    --card-foreground: 210 40% 98%;
    --popover: 222.2 84% 4.9%;
    --popover-foreground: 210 40% 98%;
    --primary: 210 40% 98%;
    --primary-foreground: 222.2 47.4% 11.2%;
    --secondary: 217.2 32.6% 17.5%;
    --secondary-foreground: 210 40% 98%;
    --muted: 217.2 32.6% 17.5%;
    --muted-foreground: 215 20.2% 65.1%;
    --accent: 217.2 32.6% 17.5%;
    --accent-foreground: 210 40% 98%;
    --destructive: 0 62.8% 30.6%;
    --destructive-foreground: 210 40% 98%;
    --border: 217.2 32.6% 17.5%;
    --input: 217.2 32.6% 17.5%;
    --ring: 212.7 26.8% 83.9%;
  }
}

@layer base {
  * {
    @apply border-gray-200;
  }
  body {
    @apply bg-background text-foreground;
  }
}
"@ | Set-Content "src/app/globals.css"

    Write-Host "✅ CSS updated" -ForegroundColor Green

    # Create GitHub Actions CI/CD
    @"
name: CI/CD Pipeline

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  test:
    runs-on: ubuntu-latest

    services:
      postgres:
        image: postgres:15-alpine
        env:
          POSTGRES_DB: ${projectName}_test
          POSTGRES_USER: postgres
          POSTGRES_PASSWORD: "@Crix13Mix01"
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
        ports:
          - 5432:5432

    strategy:
      matrix:
        node-version: [18.x, 20.x]

    steps:
    - name: Checkout code
      uses: actions/checkout@v4

    - name: Setup Node.js `${{ matrix.node-version }}
      uses: actions/setup-node@v4
      with:
        node-version: `${{ matrix.node-version }}
        cache: 'npm'

    - name: Install dependencies
      run: npm ci

    - name: Generate Prisma client
      run: npm run prisma:generate
      env:
        DATABASE_URL: postgresql://${script:DB_USERNAME}:${script:DB_PASSWORD}@localhost:5432/${projectName}_test?schema=public

    - name: Run database migrations
      run: npm run prisma:push
      env:
        DATABASE_URL: postgresql://${script:DB_USERNAME}:${script:DB_PASSWORD}@localhost:5432/${projectName}_test?schema=public

    - name: Run linting
      run: npm run lint

    - name: Run type checking
      run: npm run type-check

    - name: Build application
      run: npm run build
      env:
        DATABASE_URL: postgresql://${script:DB_USERNAME}:${script:DB_PASSWORD}@localhost:5432/${projectName}_test?schema=public

    - name: Build Docker image
      run: docker build -t $projectName:latest .
"@ | Set-Content ".github/workflows/ci.yml"

    # Create comprehensive README
    @"
# $projectName

Professional Next.js application with PostgreSQL 17.5, Prisma ORM, real user data, and optimized Docker setup.

## 🚀 Features

- ⚡ **Next.js 15+** with App Router and Server Components
- 📘 **TypeScript** for type safety
- 🎨 **Tailwind CSS** for styling
- 🗄️ **PostgreSQL 17.5 + Prisma** with real user data and optimizations
- 🐳 **Enhanced Docker** following official PostgreSQL best practices
- 👥 **Live User Management** with API routes
- 🔍 **ESLint** code quality
- 🚀 **GitHub Actions** CI/CD pipeline

## 📊 Live Data

This app includes a functional user database with:
- **User API** at `/api/users` (GET, POST)
- **User Pages** displaying real data from PostgreSQL
- **Sample Users** with username, name, and age
- **Interactive UI** with loading states and error handling

## 🏃‍♂️ Quick Start

### Option 1: Docker (Recommended)
```bash
# Start everything (database + app)
npm run docker:dev

# If you encounter caching issues, use clean build:
npm run docker:dev:clean

# View logs
npm run docker:logs

# Stop containers
npm run docker:stop
```

### Option 2: Local Development
```bash
# Copy environment file
cp .env.example .env.local

# Setup database
npm run db:setup:local

# Start development server
npm run dev
```

## 🗄️ Database Commands

```bash
# Generate Prisma client
npm run prisma:generate

# Run migrations
npm run prisma:migrate

# Seed with sample data
npm run prisma:seed

# Open Prisma Studio
npm run prisma:studio

# Complete setup (generate + migrate + seed)
npm run db:setup:local
```

## 🔧 Troubleshooting

### If Docker containers are using old/cached files:
```bash
# Force clean rebuild (bypasses all Docker caches)
npm run docker:dev:clean
```

### Database Connection Issues
```bash
# Check if PostgreSQL is running
docker-compose ps

# View database logs
docker-compose logs db

# Reset database
npm run prisma:reset
```

### Docker Build Issues
The project uses **Debian-based Docker images** to avoid Alpine Linux compatibility issues with native modules like lightningcss.

### No Users Displayed
```bash
# Seed the database
npm run prisma:seed

# Check API endpoint
curl http://localhost:3000/api/users
```

## 📁 Project Structure

```
${projectName}/
├── src/
│   ├── app/
│   │   ├── api/users/          # User API endpoints
│   │   ├── users/              # Users page
│   │   ├── about/              # About page
│   │   └── page.tsx            # Home page with live data
│   ├── components/
│   │   ├── ui/                 # Reusable UI components
│   │   └── common/             # UserList component
│   ├── lib/
│   │   ├── database/           # Prisma client
│   │   └── utils/              # Utility functions
│   └── types/
│       └── database/           # TypeScript types
├── prisma/
│   ├── schema.prisma           # Database schema
│   └── seed.ts                 # Sample data (FIXED)
├── docker-data/                # Local database files
├── docker-compose.yml          # Production Docker
├── docker-compose-dev.yml      # Development Docker
└── docs/                       # Documentation
```

## 🌐 Pages

- **/** - Home page with user stats and live data
- **/users** - Full user management interface
- **/about** - Technology stack and documentation

## 🔧 API Endpoints

- `GET /api/users` - List all users
- `POST /api/users` - Create new user

Example response:
```json
{
  "success": true,
  "data": [
    {
      "id": "clx1234567890",
      "username": "johndoe",
      "name": "John Doe",
      "age": 28,
      "email": "john.doe@example.com",
      "createdAt": "2024-01-01T00:00:00.000Z",
      "updatedAt": "2024-01-01T00:00:00.000Z"
    }
  ],
  "count": 1
}
```

## 🐳 Docker Details

### Enhanced Docker Configuration (v2.2)
- **PostgreSQL 17.5** (latest stable version)
- **Shared memory optimization** (128MB for better performance)
- **Local data volumes** (./docker-data/db for easy management)
- **Official PostgreSQL best practices** from Docker Hub documentation
- **Debian-based images** for native module compatibility
- **Health checks** for reliable startup

### Environment Variables
- `DATABASE_URL` - PostgreSQL connection string
- `NODE_ENV` - Environment (development/production)
- `NEXT_PUBLIC_APP_URL` - Application URL

## 🧪 Development

```bash
# Type checking
npm run type-check

# Code formatting
npm run lint

# Build for production
npm run build

# Start production server
npm start
```

## 🚀 Deployment

The project includes GitHub Actions workflows for:
- **Continuous Integration** - Testing and building
- **Docker Image Building** - Automated container builds
- **Production Deployment** - Ready for any platform

## 📝 Recent Updates

### v2.2 Enhancements:
- ✅ **UPGRADED:** PostgreSQL 17.5 (from 15-alpine)
- ✅ **ADDED:** Shared memory optimization (128MB)
- ✅ **IMPROVED:** Local data volumes (./docker-data/db)
- ✅ **FOLLOWING:** Official PostgreSQL Docker best practices
- ✅ **SIMPLIFIED:** Service names (database → db)

### v2.1 Fixes:
- ✅ **FIXED:** Prisma disconnect method (`$disconnect()` instead of `disconnect()`)
- ✅ **ADDED:** Docker clean build command (`npm run docker:dev:clean`)
- ✅ **IMPROVED:** Troubleshooting documentation

## 🎯 Performance Optimizations

- **PostgreSQL 17.5** with latest performance improvements
- **Shared Memory** (128MB) for faster query processing
- **Local volumes** for reduced I/O overhead
- **Health checks** for reliable container orchestration
- **Debian-based images** for better native module support

## 📝 License

This project was created with the enhanced `create-n` function and includes real functionality out of the box.
"@ | Set-Content "README.md"

    # Final success message
    Write-Host ""
    Write-Host "╭─ ✅ PROJECT CREATED SUCCESSFULLY! v2.2 ENHANCED ─────────────────────╮" -ForegroundColor Green
    Write-Host "│                                                                        │" -ForegroundColor Green
    Write-Host "│  🚀 Project: $projectName".PadRight(71) + "│" -ForegroundColor Green
    Write-Host "│  🗄️  Database: PostgreSQL 17.5 + Prisma with sample users".PadRight(71) + "│" -ForegroundColor Green
    Write-Host "│  🐳 Docker: ENHANCED (Official PostgreSQL best practices)".PadRight(71) + "│" -ForegroundColor Green
    Write-Host "│  📄 Pages: Home, Users, About with real functionality".PadRight(71) + "│" -ForegroundColor Green
    Write-Host "│  🔧 FIXED: Prisma `$disconnect() + PostgreSQL optimization".PadRight(71) + "│" -ForegroundColor Green
    Write-Host "│  📁 Location: $(Get-Location)".PadRight(71) + "│" -ForegroundColor Green
    Write-Host "│                                                                        │" -ForegroundColor Green
    Write-Host "╰────────────────────────────────────────────────────────────────────────╯" -ForegroundColor Green
    Write-Host ""
    Write-Host "🎯 Quick Start Commands:" -ForegroundColor Cyan
    Write-Host "═══════════════════════" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "🐳 Start with Docker (Recommended - includes database):" -ForegroundColor Yellow
    Write-Host "   npm run docker:dev           # Normal build" -ForegroundColor White
    Write-Host "   npm run docker:dev:clean     # Clean build (bypasses cache)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "💻 Start locally:" -ForegroundColor Yellow
    Write-Host "   npm run db:setup:local  # Setup database with sample users" -ForegroundColor DarkGray
    Write-Host "   npm run dev             # Start development server" -ForegroundColor White
    Write-Host ""
    Write-Host "🔧 v2.2 ENHANCEMENTS Applied:" -ForegroundColor Green
    Write-Host "   ✅ PostgreSQL 17.5           # UPGRADED: from 15-alpine" -ForegroundColor DarkGray
    Write-Host "   ✅ shm_size: 128mb           # ADDED: Shared memory optimization" -ForegroundColor DarkGray
    Write-Host "   ✅ Local data volumes        # IMPROVED: ./docker-data/db" -ForegroundColor DarkGray
    Write-Host "   ✅ Official best practices   # FOLLOWING: PostgreSQL docs" -ForegroundColor DarkGray
    Write-Host "   ✅ Simplified service names  # RENAMED: database → db" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "🗄️  Environment-aware database commands:" -ForegroundColor Yellow
    Write-Host "   npm run db:push:local      # Push schema to localhost DB" -ForegroundColor DarkGray
    Write-Host "   npm run db:push:docker     # Push schema to Docker DB" -ForegroundColor DarkGray
    Write-Host "   npm run db:seed:local      # Seed localhost DB" -ForegroundColor DarkGray
    Write-Host "   npm run db:seed:docker     # Seed Docker DB" -ForegroundColor DarkGray
    Write-Host "   npm run prisma:studio      # Open database admin panel" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "📊 What's included:" -ForegroundColor Cyan
    Write-Host "   👥 3 sample users (johndoe, janebrown, mikejohnson)" -ForegroundColor DarkGray
    Write-Host "   🌐 Live API at /api/users" -ForegroundColor DarkGray
    Write-Host "   📄 Functional pages: /, /users, /about" -ForegroundColor DarkGray
    Write-Host "   🎨 Beautiful UI with real data display" -ForegroundColor DarkGray
    Write-Host "   🐳 ENHANCED Docker with PostgreSQL 17.5 optimization" -ForegroundColor DarkGray
    Write-Host "   ⚙️  Dual .env files for local and Docker development" -ForegroundColor DarkGray
    Write-Host "   🔧 dotenv-cli for environment variable management" -ForegroundColor DarkGray
    Write-Host "   📁 Local Docker data in ./docker-data/ directory" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "🚀 Next steps:" -ForegroundColor Yellow
    Write-Host "   1. Run: npm run docker:dev (enhanced PostgreSQL setup)" -ForegroundColor DarkGray
    Write-Host "   2. Open: http://localhost:3000" -ForegroundColor DarkGray
    Write-Host "   3. See live user data on the homepage!" -ForegroundColor DarkGray
    Write-Host "   4. Visit /users for full user management" -ForegroundColor DarkGray
    Write-Host "   5. Check /about for tech stack details" -ForegroundColor DarkGray
    Write-Host "   6. Database files: ./docker-data/db/ (easy backup)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "💡 Database optimizations:" -ForegroundColor Yellow
    Write-Host "   🚀 PostgreSQL 17.5 (latest stable)" -ForegroundColor DarkGray
    Write-Host "   🧠 128MB shared memory for better performance" -ForegroundColor DarkGray
    Write-Host "   📁 Local volumes for easy data management" -ForegroundColor DarkGray
    Write-Host "   ✅ Health checks for reliable startup" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "💡 If you encounter Docker caching issues:" -ForegroundColor Yellow
    Write-Host "   npm run docker:dev:clean  # Forces complete rebuild" -ForegroundColor DarkGray
    Write-Host ""
}

# Create shorthand alias
function create-n {
    create-next
}
