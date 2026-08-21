local run = require("harness.run")

local BASELINE = { correct = 80, wrong = 10, false_stale = 5, correct_stale = 40 }

describe("run.compare", function()
    it("passes when the report matches the baseline", function()
        local res = run.compare(BASELINE, BASELINE)
        assert.eq(res.ok, true)
        assert.eq_deep(res.regressions, {})
    end)

    it("passes when correct goes up and wrong goes down", function()
        local better = { correct = 85, wrong = 6, false_stale = 5, correct_stale = 44 }
        assert.eq(run.compare(better, BASELINE).ok, true)
    end)

    it("fails when wrong placements increase", function()
        local worse = { correct = 80, wrong = 11, false_stale = 5, correct_stale = 40 }
        local res = run.compare(worse, BASELINE)
        assert.eq(res.ok, false)
        assert.eq(#res.regressions, 1)
        assert.match(res.regressions[1], "wrong")
    end)

    it("fails when correct placements decrease", function()
        local worse = { correct = 79, wrong = 10, false_stale = 5, correct_stale = 40 }
        local res = run.compare(worse, BASELINE)
        assert.eq(res.ok, false)
        assert.match(res.regressions[1], "correct")
    end)

    it("reports both regressions at once", function()
        local worse = { correct = 70, wrong = 20, false_stale = 5, correct_stale = 40 }
        assert.eq(#run.compare(worse, BASELINE).regressions, 2)
    end)
end)

describe("run.measure", function()
    it("scores a real repository and classifies every sample", function()
        local dir = vim.fn.tempname()
        vim.fn.mkdir(dir, "p")
        local function sh(cmd)
            local out =
                vim.fn.system({ "sh", "-c", ("cd %s && %s"):format(vim.fn.shellescape(dir), cmd) })
            assert(vim.v.shell_error == 0, out)
        end
        sh("git init -q && git config user.email t@t && git config user.name t")
        sh("seq 1 200 | sed 's/^/line /' > f.txt")
        sh("git add f.txt && git commit -qm one")
        sh("(echo inserted; cat f.txt) > tmp && mv tmp f.txt")
        sh("git add f.txt && git commit -qm two")

        local report = run.measure({
            repo = dir,
            path = "f.txt",
            depth = 1,
            samples = 20,
            height = 3,
        })

        assert.eq(report.samples, 20)
        assert.eq(
            report.correct + report.wrong + report.false_stale + report.correct_stale,
            report.samples
        )

        -- A pure insertion above every sampled block must relocate them all
        assert.eq(report.wrong, 0)
        assert.gt(report.correct, 0)
    end)
end)
